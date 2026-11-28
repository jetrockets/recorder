# frozen_string_literal: true

require 'rails_helper'

# The concern is included inside `controller` blocks, where `described_class`
# is not defined.
# rubocop:disable RSpec/DescribedClass
RSpec.describe Recorder::Rails::ControllerConcern, type: :controller do
  controller(ActionController::Base) do
    include Recorder::Rails::ControllerConcern

    def index
      head :ok
    end
  end

  before { routes.draw { get 'index' => 'anonymous#index' } }

  it 'keeps the request context before the action runs' do
    get :index

    expect(Recorder.store.params).to include(ip: '0.0.0.0', action_date: Date.current, user_id: nil, meta: nil)
  end

  it 'leaves the user blank when the controller has no current_user' do
    get :index

    expect(Recorder.store.params[:user_id]).to be_nil
  end

  context 'when current_user returns a record' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def index
        head :ok
      end

      private

      def current_user
        User.new(id: 7)
      end
    end

    it 'keeps its id' do
      get :index

      expect(Recorder.store.params[:user_id]).to eq(7)
    end

    it 'calls current_user once' do
      allow(controller).to receive(:current_user).and_call_original

      get :index

      expect(controller).to have_received(:current_user).once
    end

    it 'lets a NoMethodError raised by its id through' do
      user = User.new(id: 7)
      allow(user).to receive(:id).and_raise(NoMethodError, 'broken id')
      allow(controller).to receive(:current_user).and_return(user)

      expect { get :index }.to raise_error(NoMethodError, 'broken id')
    end

    context 'when the record is wrapped in a proxy' do
      let(:proxy_without_respond_to_missing) do
        Class.new do
          def initialize(user)
            @user = user
          end

          def method_missing(name, *args, &block) # rubocop:disable Style/MissingRespondToMissing
            @user.public_send(name, *args, &block)
          end
        end
      end

      let(:proxy_without_respond_to) do
        Class.new(BasicObject) do
          def initialize(user)
            @user = user
          end

          def id
            @user.id
          end
        end
      end

      def wrap_current_user_in(proxy_class)
        allow(controller).to receive(:current_user).and_wrap_original { |original| proxy_class.new(original.call) }
      end

      it 'keeps the id that a proxy with respond_to_missing? forwards' do
        wrap_current_user_in(SimpleDelegator)

        get :index

        expect(Recorder.store.params[:user_id]).to eq(7)
      end

      it 'keeps a proxy that answers id only through method_missing as it is' do
        wrap_current_user_in(proxy_without_respond_to_missing)

        get :index
        security = Security.create!(name: 'Facebook', identifier: 'FB')

        expect(Recorder.store.params[:user_id]).to be_a(proxy_without_respond_to_missing)
        expect(security.revisions.last.user_id).to be_nil
      end

      it 'raises for a proxy that does not implement respond_to?' do
        wrap_current_user_in(proxy_without_respond_to)

        expect { get :index }.to raise_error(NoMethodError, /respond_to\?/)
      end
    end
  end

  context 'when current_user returns the id itself' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def index
        head :ok
      end

      private

      def current_user
        42
      end
    end

    it 'keeps it as it is' do
      get :index

      expect(Recorder.store.params[:user_id]).to eq(42)
    end

    it 'calls current_user once' do
      allow(controller).to receive(:current_user).and_call_original

      get :index

      expect(controller).to have_received(:current_user).once
    end

    it 'keeps a String id as it is, with one call' do
      allow(controller).to receive(:current_user).and_return('9f1c2d3e-0000-4000-8000-000000000001')

      get :index

      expect(Recorder.store.params[:user_id]).to eq('9f1c2d3e-0000-4000-8000-000000000001')
      expect(controller).to have_received(:current_user).once
    end
  end

  context 'when current_user returns nil' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def index
        head :ok
      end

      private

      def current_user
        nil
      end
    end

    it 'leaves the user blank and calls current_user once' do
      allow(controller).to receive(:current_user).and_call_original

      get :index

      expect(Recorder.store.params).to include(user_id: nil)
      expect(controller).to have_received(:current_user).once
    end
  end

  context 'when current_user raises NoMethodError' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def index
        head :ok
      end

      private

      def current_user
        raise NoMethodError, 'broken current_user'
      end
    end

    it 'lets it through after one call' do
      allow(controller).to receive(:current_user).and_call_original

      expect { get :index }.to raise_error(NoMethodError, 'broken current_user')
      expect(controller).to have_received(:current_user).once
    end
  end

  context 'when the controller overrides recorder_meta' do
    controller(ActionController::Base) do
      include Recorder::Rails::ControllerConcern

      def index
        head :ok
      end

      private

      def recorder_meta
        {locale: 'en'}
      end
    end

    it 'keeps it in the request context' do
      get :index

      expect(Recorder.store.params[:meta]).to eq(locale: 'en')
    end

    it 'writes it on the revisions that follow' do
      get :index
      security = Security.create!(name: 'Facebook', identifier: 'FB')

      expect(security.revisions.last.meta).to eq('locale' => 'en')
    end
  end
end
# rubocop:enable RSpec/DescribedClass
