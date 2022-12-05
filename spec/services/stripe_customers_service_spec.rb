require 'rails_helper'
require 'csv'

RSpec.describe StripeCustomersService do
  let(:service_call) { StripeCustomersService.fetch_to_csv }
  let(:mocked_last_request) do
    allow(Stripe::Customer).to receive(:list).with({ limit: 50, starting_after: nil }).and_return(mocked_last_response)
  end
  let(:mocked_last_response) do
    { object: 'list',
      data: [{ id: 123, name: 'Quim Porta', email: 'test@the.email', rubish: 'No needed' },
             last_line],
      has_more: false,
      url: 'url/1' }
  end

  let(:last_line) { { id: 456, name: 'Joaking Door', email: 'another@test.email', rubish: 'No needed' } }
  let(:mocked_last_id) { mocked_last_response[:data].last[:id] }

  let(:mocked_csv_handler) { allow(CsvHandler).to receive(:new).and_return(mocked_csv_instance) }
  let(:mocked_csv_instance) { instance_double(CsvHandler) }
  let(:mocked_csv_methods) do
    allow(mocked_csv_instance).to receive(:read_last_line).and_return(last_line_on_csv)
    allow(mocked_csv_instance).to receive(:add_lines)
  end

  before do
    mocked_last_request
    mocked_csv_handler
    mocked_csv_methods
  end

  context 'when working properly' do
    let(:last_line_on_csv) { nil }

    it 'is expected to set the api secret key' do
      api_secret_key = 'sk_test_RsUIbMyxLQszELZQEXHTeFA9008YRV7Vhr'
      expect { service_call }.to change { Stripe.api_key }.to api_secret_key
    end

    it 'is expected to return true' do
      expect(service_call).to be true
    end

    it 'is expected to send requests to the Stripe Api and with the correct params' do
      allow(Stripe::Customer).to receive(:list).with({ limit: 50, starting_after: nil }).and_call_original
      allow(Stripe::Customer).to receive(:list).and_return(mocked_last_response)
      service_call

      expect(Stripe::Customer).to have_received(:list).with({ limit: 50, starting_after: nil }).once
    end

    context 'when expecting multiple batchs of data' do
      let(:first_batch) do
        { object: 'list',
          data: [{ id: 0o000, name: 'Test', email: 'fa@the.email', rubish: 'No needed' },
                 { id: first_batch_last_id, name: 'Test', email: 'fa@the.email', rubish: 'No needed' }],
          has_more: true,
          url: 'url/1' }
      end
      let(:first_batch_last_id) { 123_123 }

      before do
        allow(Stripe::Customer).to receive(:list).with({ limit: 50, starting_after: nil }).and_return(first_batch)
        allow(Stripe::Customer).to receive(:list).with({ limit: 50,
                                                         starting_after: first_batch_last_id }).and_return(mocked_last_response)
        service_call
      end

      it 'is expected to send another request' do
        expect(Stripe::Customer).to have_received(:list).with({ limit: 50, starting_after: nil }).once
        expect(Stripe::Customer).to have_received(:list).with({ limit: 50,
                                                                starting_after: first_batch_last_id }).once
        expect(Stripe::Customer).to have_received(:list).twice
      end

      it 'is expected to call the CsvHandler saver method once per batch containing the correct data' do
        expect(mocked_csv_instance).to have_received(:add_lines).with(first_batch[:data].pluck(:id, :name, :email)).once
        expect(mocked_csv_instance).to have_received(:add_lines).with(mocked_last_response[:data].pluck(:id, :name,
                                                                                                        :email)).once
      end
    end

    context 'when expecting only one batch' do
      before do
        allow(Stripe::Customer).to receive(:list).with({ limit: 50,
                                                         starting_after: nil }).and_return(mocked_last_response)
        service_call
      end

      it 'is expected to send a request once' do
        expect(Stripe::Customer).to have_received(:list).once
      end

      it 'is expected to call the CsvHandler saver method once' do
        expect(mocked_csv_instance).to have_received(:add_lines).once
      end
    end
  end

  context 'when app is killed while service is running' do
    let(:last_saved_id) { 'last_saved_id' }
    let(:last_line_on_csv) { [last_saved_id, 'last_name', 'last_email'] }

    before do
      allow(Stripe::Customer).to receive(:list).with({ limit: 50,
                                                       starting_after: last_saved_id }).and_return mocked_last_response
    end

    it 'is expected to request the data after last saved id' do
      service_call
      expect(Stripe::Customer).to have_received(:list).with({ limit: 50, starting_after: last_saved_id }).once
    end

    it 'is expected to return true' do
      expect(service_call).to be true
    end
  end

  context 'when Stripe responds with a Rate Limit Error' do
    let(:last_line_on_csv) { nil }
    before { allow(Stripe::Customer).to receive(:list).and_raise(Stripe::RateLimitError) }

    context 'when called_by_job = true' do
      it 'is expected to raise the same error' do
        expect { StripeCustomersService.fetch_to_csv(true) }.to raise_error Stripe::RateLimitError
      end
    end

    context 'when called_by_job = false' do
      it 'is expected to return false' do
        expect(service_call).to be false
      end

      it 'is expected to schedule a sidekiq job' do
        allow(StripeCustomersJob).to receive(:perform_later)

        service_call
        expect(StripeCustomersJob).to have_received(:perform_later).once
      end
    end
  end
end
