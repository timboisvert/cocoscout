require 'rails_helper'

RSpec.describe AuditionRequest, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      request = build(:audition_request)
      expect(request).to be_valid
    end

    context "when call_to_audition is video_upload type" do
      it "is invalid without a video_url" do
        call = create(:call_to_audition, :video_upload)
        request = build(:audition_request, call_to_audition: call, video_url: nil)

        expect(request).not_to be_valid
        expect(request.errors[:video_url]).to include("can't be blank")
      end

      it "is valid with a video_url" do
        call = create(:call_to_audition, :video_upload)
        request = build(:audition_request, :with_video, call_to_audition: call)

        expect(request).to be_valid
      end
    end

    context "when call_to_audition is in_person type" do
      it "is valid without a video_url" do
        call = create(:call_to_audition, audition_type: :in_person)
        request = build(:audition_request, call_to_audition: call, video_url: nil)

        expect(request).to be_valid
      end
    end
  end

  describe "associations" do
    it "belongs to call_to_audition" do
      request = create(:audition_request)
      expect(request.call_to_audition).to be_present
      expect(request).to respond_to(:call_to_audition)
    end

    it "belongs to person" do
      request = create(:audition_request)
      expect(request.person).to be_present
      expect(request).to respond_to(:person)
    end

    it "has many answers" do
      request = create(:audition_request)
      expect(request).to respond_to(:answers)
    end
  end

  describe "status enum" do
    it "can be unreviewed" do
      request = create(:audition_request, status: :unreviewed)
      expect(request.unreviewed?).to be true
    end

    it "can be undecided" do
      request = create(:audition_request, :undecided)
      expect(request.undecided?).to be true
    end

    it "can be passed" do
      request = create(:audition_request, :passed)
      expect(request.passed?).to be true
    end

    it "can be accepted" do
      request = create(:audition_request, :accepted)
      expect(request.accepted?).to be true
    end
  end

  describe "#display_name" do
    it "returns the person's name" do
      person = create(:person, name: "John Doe")
      request = create(:audition_request, person: person)

      expect(request.display_name).to eq("John Doe")
    end
  end

  describe "#next" do
    let(:call) { create(:call_to_audition) }

    it "returns the next audition request created after this one" do
      request1 = create(:audition_request, call_to_audition: call, created_at: 1.hour.ago)
      request2 = create(:audition_request, call_to_audition: call, created_at: 30.minutes.ago)
      request3 = create(:audition_request, call_to_audition: call, created_at: 10.minutes.ago)

      expect(request1.next).to eq(request2)
      expect(request2.next).to eq(request3)
    end

    it "returns nil when there is no next request" do
      request = create(:audition_request, call_to_audition: call)
      expect(request.next).to be_nil
    end
  end

  describe "#previous" do
    let(:call) { create(:call_to_audition) }

    it "returns the previous audition request created before this one" do
      request1 = create(:audition_request, call_to_audition: call, created_at: 1.hour.ago)
      request2 = create(:audition_request, call_to_audition: call, created_at: 30.minutes.ago)
      request3 = create(:audition_request, call_to_audition: call, created_at: 10.minutes.ago)

      expect(request3.previous).to eq(request2)
      expect(request2.previous).to eq(request1)
    end

    it "returns nil when there is no previous request" do
      request = create(:audition_request, call_to_audition: call)
      expect(request.previous).to be_nil
    end
  end

  describe "with answers" do
    it "can have multiple answers" do
      request = create(:audition_request)
      question1 = create(:question, questionable: request.call_to_audition)
      question2 = create(:question, questionable: request.call_to_audition)

      answer1 = create(:answer, audition_request: request, question: question1, value: "Answer 1")
      answer2 = create(:answer, audition_request: request, question: question2, value: "Answer 2")

      expect(request.answers).to include(answer1, answer2)
      expect(request.answers.count).to eq(2)
    end

    it "destroys associated answers when destroyed" do
      request = create(:audition_request)
      question = create(:question, questionable: request.call_to_audition)
      create(:answer, audition_request: request, question: question)

      expect { request.destroy }.to change { Answer.count }.by(-1)
    end
  end
end
