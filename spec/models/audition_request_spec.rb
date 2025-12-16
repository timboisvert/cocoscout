# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditionRequest, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      request = build(:audition_request)
      expect(request).to be_valid
    end

    context 'when audition_cycle is video_upload type' do
      it 'is invalid without a video_url' do
        call = create(:audition_cycle, :video_upload)
        request = build(:audition_request, audition_cycle: call, video_url: nil)

        expect(request).not_to be_valid
        expect(request.errors[:video_url]).to include("can't be blank")
      end

      it 'is valid with a video_url' do
        call = create(:audition_cycle, :video_upload)
        request = build(:audition_request, :with_video, audition_cycle: call)

        expect(request).to be_valid
      end
    end

    context 'when audition_cycle is in_person type' do
      it 'is valid without a video_url' do
        call = create(:audition_cycle, audition_type: :in_person)
        request = build(:audition_request, audition_cycle: call, video_url: nil)

        expect(request).to be_valid
      end
    end
  end

  describe 'associations' do
    it 'belongs to audition_cycle' do
      request = create(:audition_request)
      expect(request.audition_cycle).to be_present
      expect(request).to respond_to(:audition_cycle)
    end

    it 'belongs to person' do
      request = create(:audition_request)
      expect(request.person).to be_present
      expect(request).to respond_to(:person)
    end

    it 'has many answers' do
      request = create(:audition_request)
      expect(request).to respond_to(:answers)
    end
  end

  describe 'status enum' do
    it 'can be pending' do
      request = create(:audition_request, status: :pending)
      expect(request.pending?).to be true
    end

    it 'can be approved' do
      request = create(:audition_request, :approved)
      expect(request.approved?).to be true
    end

    it 'can be rejected' do
      request = create(:audition_request, :rejected)
      expect(request.rejected?).to be true
    end
  end

  describe '#display_name' do
    it "returns the person's name" do
      person = create(:person, name: 'John Doe')
      request = create(:audition_request, requestable: person)

      expect(request.display_name).to eq('John Doe')
    end
  end

  describe '#next' do
    let(:call) { create(:audition_cycle) }

    it 'returns the next audition request created after this one' do
      request1 = create(:audition_request, audition_cycle: call, created_at: 1.hour.ago)
      request2 = create(:audition_request, audition_cycle: call, created_at: 30.minutes.ago)
      request3 = create(:audition_request, audition_cycle: call, created_at: 10.minutes.ago)

      expect(request1.next).to eq(request2)
      expect(request2.next).to eq(request3)
    end

    it 'returns nil when there is no next request' do
      request = create(:audition_request, audition_cycle: call)
      expect(request.next).to be_nil
    end
  end

  describe '#previous' do
    let(:call) { create(:audition_cycle) }

    it 'returns the previous audition request created before this one' do
      request1 = create(:audition_request, audition_cycle: call, created_at: 1.hour.ago)
      request2 = create(:audition_request, audition_cycle: call, created_at: 30.minutes.ago)
      request3 = create(:audition_request, audition_cycle: call, created_at: 10.minutes.ago)

      expect(request3.previous).to eq(request2)
      expect(request2.previous).to eq(request1)
    end

    it 'returns nil when there is no previous request' do
      request = create(:audition_request, audition_cycle: call)
      expect(request.previous).to be_nil
    end
  end

  describe 'with answers' do
    it 'can have multiple answers' do
      request = create(:audition_request)
      question1 = create(:question, questionable: request.audition_cycle)
      question2 = create(:question, questionable: request.audition_cycle)

      answer1 = create(:answer, audition_request: request, question: question1, value: 'Answer 1')
      answer2 = create(:answer, audition_request: request, question: question2, value: 'Answer 2')

      expect(request.answers).to include(answer1, answer2)
      expect(request.answers.count).to eq(2)
    end

    it 'destroys associated answers when destroyed' do
      request = create(:audition_request)
      question = create(:question, questionable: request.audition_cycle)
      create(:answer, audition_request: request, question: question)

      expect { request.destroy }.to change { Answer.count }.by(-1)
    end
  end
end
