# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recorder::Sidekiq::RevisionsWorker do
  let(:user) { User.create!(name: 'Igor') }

  before do
    Recorder.info = {user_id: user.id}
    Recorder.meta = {status: :active, recorded_on: Date.new(2026, 8, 25)}
  end

  # The arguments `record_async` enqueues, as Sidekiq hands them back to
  # `perform` after holding them on Redis as JSON.
  def enqueued_job_arguments
    arguments = nil
    worker = class_double(described_class)
    allow(worker).to receive(:perform_in) { |_delay, params| arguments = params }
    stub_const('Recorder::Sidekiq::RevisionsWorker', worker)

    Recorder.config.async = true
    Security.create!(name: 'Facebook', identifier: 'FB')

    JSON.parse(arguments.to_json)
  end

  def perform_enqueued_job
    described_class.new.perform(enqueued_job_arguments)
    Recorder::Revision.last
  end

  it 'writes the revision the enqueueing create did not' do
    expect { perform_enqueued_job }.to change(Recorder::Revision, :count).by(1)
  end

  it 'stores data as a JSON object rather than the string it travelled as' do
    expect(perform_enqueued_job.data).to include('attributes', 'changes')
  end

  it 'stores action_date as a date' do
    expect(perform_enqueued_job.action_date).to eq(Date.today)
  end

  it 'stores meta as the synchronous path stores it' do
    Security.create!(name: 'Twitter', identifier: 'TWTR')
    synchronous = Recorder::Revision.last

    expect(perform_enqueued_job.meta).to eq(synchronous.meta)
  end
end
