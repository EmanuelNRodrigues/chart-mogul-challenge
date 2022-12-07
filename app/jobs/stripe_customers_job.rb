require 'redis'

# Job that calls the StripeCustomersService.
# This job also records the number of retries and exponentially increases the
# interval time between each try.
class StripeCustomersJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 5

  # This class is just a representation of my intention to handle the limit rates,
  # I think this really needs to improve.
  def perform
    redis = Redis.new
    retry_count = redis.get('retry_count').to_i

    StripeCustomersService.fetch_to_csv(true)
  rescue Stripe::RateLimitError
    redis.set('retry_count', retry_count + 1)
    seconds_to_retry = 2**retry_count + rand(0.00 + 0.1)
    puts "Retry count: #{retry_count}. Will retry again in #{seconds_to_retry.to_i} seconds."
    perform_at(seconds_to_retry.seconds.from_now) # This is not working but i think it's understandable my intention.
  end
end
