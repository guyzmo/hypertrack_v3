[![Gem Version](https://badge.fury.io/rb/hypertrack_v3.svg)](https://badge.fury.io/rb/hypertrack_v3)

# Hypertrack RubyGem

A RubyGem for [Hypertrack](https://www.hypertrack.com/)'s [Backend API Version 3](https://docs.hypertrack.com/#references-apis)

## Installation

Add this line to your application's Gemfile:
```ruby
gem 'hypertrack_v3'
```

And then run `bundle install` on command line.

Or install it yourself as: `gem install hypertrack_v3`

## Initialization

### For the webhooks

The webhooks are only available if used with rails (it is declared as a rails engine),
so you should add a `config/initializers/hypertrack_v3.rb` file, such as:

```ruby
require 'hypertrack_v3'

HypertrackV3.error_handler = ->(msg, **args) { Raven.capture_message(msg, **args) }
HypertrackV3.exception_handler = ->(exc, **args) { Raven.capture_exception(exc, **args) }

class ::HypertrackV3::Engine::WebhookParser
  register_hook :location, lambda { |device_id, data, created_at, recorded_at|
    Rails.logger.debug("LocationHook: #{device_id} -> #{data}")
  }

  register_hook :device_status, lambda { |device_id, data, created_at, recorded_at|
    Rails.logger.debug("DeviceStatusHook: #{device_id} -> #{data}")
  }

  register_hook :battery, lambda { |device_id, data, created_at, recorded_at|
    Rails.logger.debug("BatteryHook: #{device_id} -> #{data}")
  }

  register_hook :trip, lambda { |device_id, data, created_at, recorded_at|
    Rails.logger.debug("TripHook: #{device_id} -> #{data}")
  }
end
```

Instead of just logging when using the hooks, you should do something with them.

Then in your application's `routes.rb`, simply mount the engine:

```ruby
Rails.application.routes.draw do
  # ...
  mount HypertrackV3::Engine => 'webhook/hypertrack'
end
```

There on your hypertrack dashboard, you can declare your webhook as `https://yoursite.tld/webhook/hypertrack`.
Click on the test webhook button, and you should be all set.

### For the client API

Wherever you need to use the HypertrackV3 API client, simply instantiate the client using:

```ruby
HypertrackV3.new(
  ENV['HYPERTRACK_ACCOUNT_ID'],
  ENV['HYPERTRACK_SECRET_KEY']
)
```

Obviously, it's always better to keep secrets in the environment.

## Usage

The API client is very simple, and here are the implemented methods:

* [`device_list()`][1]: List all devices
* [`device_get(id:)`][2]: Gets a device (given a device id)
* [`device_del(id:)`][3]: Deletes a device (given a device id)
* [`trip_create(device_id:, destination:, geofences:, metadata:)`][5]: Creates a trip
  * `device_id` is a device's id (obviously)
  * `destination` is a GeoJSON formatted location
  * `geofences` is a list that details the geofences that trigger that trip ([RTFM][5])
  * `metadata` is a hash containing any string you want to associate to the trip
* [`trip_list(limit, offset)`][6]: Lists all trips (you can easily paginate using limit and offset)
* [`trip_get(id:)`][7]: Gets a trip given its id
* [`trip_set_complete(id:)`][8]: Sets a trip as complete, given its id

> TODO
> * [`device_update(id:, ...)`][4]: Updates a device (given a device id and ...)

[1]:https://docs.hypertrack.com/#references-apis-devices-get-devices
[2]:https://docs.hypertrack.com/#references-apis-devices-get-devices-device_id
[3]:https://docs.hypertrack.com/#references-apis-devices-delete-devices-device_id
[4]:https://docs.hypertrack.com/#references-apis-devices-patch-devices-device_id
[5]:https://docs.hypertrack.com/#references-apis-trips-post-trips
[6]:https://docs.hypertrack.com/#references-apis-trips-get-trips
[7]:https://docs.hypertrack.com/#references-apis-trips-get-trips-trip_id
[8]:https://docs.hypertrack.com/#references-apis-trips-post-trips-trip_id-complete

All data is returned as an OpenStruct hash, so it's easy to use and manipulate.
For more information, please refer to [the official documentation](https://docs.hypertrack.com/#references-apis)

The Webhooks follow the same principles, and the following ones are implemented:

* [`location` hook](https://docs.hypertrack.com/#references-webhooks-location-payload)
* [`device_status` hook](https://docs.hypertrack.com/#references-webhooks-device-status-payload)
* [`battery` hook](https://docs.hypertrack.com/#references-webhooks-battery-payload)
* [`trip` hook](https://docs.hypertrack.com/#references-webhooks-trip-payload)

Each webhook receives a bunch of parameters, and again the data parameter is an OpenStruct hash
for easy manipulation. It's blindly implementing the payload format.

## Dependency injection

To help catch errors nicely, you can inject an error tracking tool using dependency injection,
then for every error being returned by the webhooks you'll get a nice trace in your favourite
tool. For example to implement sentry, you can add to the initializer:

```ruby
HypertrackV3.error_handler = ->(msg, **args) { Raven.capture_message(msg, **args) }
HypertrackV3.exception_handler = ->(exc, **args) { Raven.capture_exception(exc, **args) }
```

## License

LGPL License

Copyright (c) 2019 Bernard Pratz

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

