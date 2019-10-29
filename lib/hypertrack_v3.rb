# frozen_string_literal: true

class HypertrackV3
  BASE_URL='https://v3.api.hypertrack.com'

  RES_DEVICES = '/devices'
  RES_DEVICE = "/devices/%{device_id}"
  RES_TRIPS = "/trips"
  RES_TRIP = "/trips/%{trip_id}"
  RES_TRIP_COMPLETE = "/trips/%{trip_id}/complete"

  class HttpError < StandardError
    attr_reader :code
    attr_reader :message

    def initialize(code, message)
      @code = code
      @message = message
    end
  end

  class InternalServerError < HttpError; end
  class ClientError < HttpError; end

  class RegisterHookError < StandardError; end

  def initialize(account_id, secret_key)
    @client = nil
    @account_id = account_id
    @secret_key = secret_key
  end

  def client
    @client ||= Faraday.new url: self.class::BASE_URL do |conn|
      conn.basic_auth(@account_id, @secret_key)
      conn.request :json
      conn.response :json, :content_type => /\bjson$/
      conn.response :json, :parser_options => { :object_class => OpenStruct }
      conn.use Faraday::Response::Logger, HypertrackV3.logger, bodies: true
      conn.use :instrumentation
      conn.adapter Faraday.default_adapter
    end
  end

  def parse(res)
    raise InternalServerError.new(res.status, res.body) if res.status >= 500
    raise ClientError.new(res.status, res.body) if res.status >= 400
    raise HttpError.new(res.status, res.body) unless res.success?
    res.body
  end

  def device_list
    parse(client.get(self.class::RES_DEVICES))
  end

  def device_get(id:, **)
    parse(client.get(self.class::RES_DEVICE % {device_id: id}))
  end

  def device_del(id:, **)
    parse(client.delete(self.class::RES_DEVICE % {device_id: id}))
  end

  def trip_create(
      device_id:,
      destination:,
      geofences:,
      metadata:, **)
    parse(
      client.post(self.class::RES_TRIPS) do |req|
        req.body = {
          device_id: device_id,
          destination: destination,
          geofences: geofences,
          metadata: metadata,
        }
      end
    )
  end

  def trip_list(limit=50, offset=0)
    parse(client.get(self.class::RES_TRIPS, params={limit: limit, offset: offset}))
  end

  def trip_get(id:, **)
    parse(client.get(self.class::RES_TRIP % {trip_id: id}))
  end

  def trip_set_complete(id:, **)
    parse(client.post(self.class::RES_TRIP_COMPLETE % {trip_id: id}))
  end

  def self.logger
    @@logger ||= defined?(Rails) ? Rails.logger : Logger.new(STDOUT)
  end

  def self.logger=(logger)
    @@logger = logger
  end

  def self.error_handler
    @@error_handler ||= ->(*, **) { nil }
  end

  def self.error_handler=(error_handler)
    @@error_handler = error_handler
  end

  def self.exception_handler
    @@error_handler ||= ->(*, **) { nil }
  end

  def self.exception_handler=(error_handler)
    @@error_handler = error_handler
  end

  def self.log_error(message, **data)
    self.logger.error({message: message}.merge(data))
    self.error_handler.(message, **data)
  end

  def self.log_exception(exception, **data)
    self.logger.error({exception: exception.as_json}.merge(data))
    self.exception_handler.(exception, **data)
  end
end

if defined? Rails
  class HypertrackV3::Engine < Rails::Engine
    class WebhookParser
      class LogHook
        def self.call(type, device_id, data, created_at, recorded_at)
          HypertrackV3.logger.debug("HypertrackV3::LogHook#{type}: #{device_id} -> #{data}")
        end
      end

      def self.client
        @@client ||= Faraday.new do |conn|
          conn.use Faraday::Response::Logger, HypertrackV3.logger, bodies: true
          conn.use :instrumentation
          conn.adapter Faraday.default_adapter
        end
      end

      @@client = nil

      # Sets up default hooks
      @@hooks = {
        location: ->(*args) { LogHook.('Location', *args) },
        device_status: ->(*args)  { LogHook.('DeviceStatus', *args) },
        battery: ->(*args)  { LogHook.('Battery', *args) },
        trip: ->(*args)  { LogHook.('Trip', *args) },
      }

      def self.register_with_hypertrack(request)
        register_data = JSON.parse(request.body)

        resp = self.client.get register_data["SubscribeURL"]
        data = Nokogiri::XML(resp.body)
        data.remove_namespaces!
        token = data.at_xpath('//SubscriptionArn')&.content
        return self.serve(400, {error: 'SubscriptionArn not found'}) if token.empty?
        Rails.cache.write('/hypertrack_v3/subscription_arn', token, expires_in: 100.years)

        self.serve(200)
      end

      def self.dispatch(request)
        if (cached = Rails.cache.fetch('/hypertrack_v3/subscription_arn')) != request.headers['x_amz_sns_subscription_arn']
          HypertrackV3.log_error(
            "invalid subscription-arn header",
            {
              subscription_arn: {
                request: request.header,
                cache: cached,
              }
            }.to_json
          )
          return self.serve(400, {error: "invalid subscription-arn header"})
        end
        if (cached = Rails.cache.fetch("/hypertrack_v3/#{request.headers['x_amz_sns_message_id']}")).present?
          HypertrackV3.log_error(
            "Message Id already seen",
            {
              sns_message_id: {
                request: request.headers['x_amz_sns_message_id'],
                cache: cached,
              }
            }
          )
          return self.serve(400)
        end
        Rails.cache.write(
          "/hypertrack_v3/#{request.headers['x_amz_sns_message_id']}", true,
          expires_in: 1.hour
        )

        begin
          data = JSON.parse(request.body, object_class: OpenStruct)
        rescue JSON::ParserError => err
          HypertrackV3.log_exception(err)
        end

        res = true
        data.each do |datum|
          if @@hooks.include? datum.type.to_sym
            res &= @@hooks[datum.type.to_sym].(datum.device_id, datum.data, datum.created_at, datum.recorded_at)
          else
            res = false
          end
        end

        self.serve(res ? 200 : 400)
      end

      def self.register_hook(name, callable)
        raise RegisterHookError("Invalid name argument: #{name}") unless @@hooks.keys.include? name.to_sym
        raise RegisterHookError("Invalid callable argument: #{callable}") unless callable.respond_to? :call
        @@hooks[name.to_sym] = callable
      end

      def self.call(env)
        request = parse_request(env)

        case request.headers['x_amz_sns_message_type']
        when 'SubscriptionConfirmation'
          self.register_with_hypertrack request
        when 'Notification'
          self.dispatch request
        else
          HypertrackV3.log_error(
            "invalid message-type header",
            {
              message_type: request.header['x_amz_sns_messate_type'],
            }.to_json
          )
          self.serve(400, {error: "invalid message-type header"})
        end
      end

      def self.parse_request(env)
        OpenStruct.new({
          headers: env.select {|k,v| k.to_s.start_with? 'HTTP_'}
                      .collect {|key, val| [key.to_s.sub(/^HTTP_/, '').downcase, val]}.to_h,
          params: env['rack.request.query_hash'],
          body: env['rack.input']&.read
        })
      end

      def self.serve(code, params={})
        [
          code,
          {"Content-Type" => "application/json; charset=utf-8"},
          [params.to_json]
        ]
      end
    end

    endpoint WebhookParser
  end
end

