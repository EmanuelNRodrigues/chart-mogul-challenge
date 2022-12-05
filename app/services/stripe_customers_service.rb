require 'stripe'
require 'byebug'
require 'redis'

# Class that requests a list of Stripes Customers and saves their id, name and email
# This Service uses the stripe gem to handle the request.
class StripeCustomersService
  class << self
    # Fetchs customers data from https://api.stripe.com/.
    # Receives the data in batches of 50 customers then calls the service that
    # handles saving data in a .csv.
    # Returns true if service works as intended or
    # calls the StripeCustomersJob and returns a false if an RateLimitError was raised.
    # If the service was called from the StripeCustomersJob and raises a RateLimitError,
    # the error will be handled at the JOB.
    def fetch_to_csv(called_by_job = false)
      set_api_secret_key
      @csv_handler = CsvHandler.new('app/services/customers_info.csv')
      request_and_save_customers_data

      clean_redis if called_by_job
      true
    rescue Stripe::RateLimitError => e
      raise e if called_by_job

      puts 'You made too many API calls in too short a time.'
      StripeCustomersJob.perform_later
      false
    end

    private

    # Sets the api secret key needed to validate credentials
    def set_api_secret_key
      Stripe.api_key = 'sk_test_RsUIbMyxLQszELZQEXHTeFA9008YRV7Vhr'
    end

    # Checks if exists an saved id on the CSV, if exists fetchs data from there,
    # if not, starts from the beginning.
    # If Stripe responds has a response[:has_more] = true, checks the last saved id and
    # makes another request to the Stripe API
    def request_and_save_customers_data
      last_customer_id_saved = last_id_on_csv
      loop do
        # response = { object: contains the called method,
        #              data: contains the customers data,
        #              has_more: boolean related to if there's more info in the Stripe DB,
        #              url: contains the request url }
        response = Stripe::Customer.list({ limit: 50, starting_after: last_customer_id_saved })
        handle_customer_data(response[:data])
        break unless response[:has_more]

        last_customer_id_saved = response[:data].last[:id]
      end
    end

    # Returns the last id saved on the CSV
    def last_id_on_csv
      @csv_handler.read_last_line&.first
    end

    # Selects the pretended data and calls the csv handler to save it
    def handle_customer_data(data)
      customers_data_to_save = data.pluck(:id, :name, :email)
      @csv_handler.add_lines(customers_data_to_save)
    end

    # Cleans Redis key value at Database
    def clean_redis
      Redis.new.del('retry_count')
    end
  end
end
