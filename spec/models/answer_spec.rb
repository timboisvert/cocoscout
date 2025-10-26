require 'rails_helper'

RSpec.describe Answer, type: :model do
  describe "associations" do
    it "belongs to question" do
      answer = create(:answer)
      expect(answer.question).to be_present
      expect(answer).to respond_to(:question)
    end

    it "belongs to audition_request" do
      answer = create(:answer)
      expect(answer.audition_request).to be_present
      expect(answer).to respond_to(:audition_request)
    end
  end

  describe "creating answers" do
    it "can be created with value" do
      audition_request = create(:audition_request)
      question = create(:question, questionable: audition_request.call_to_audition)
      answer = Answer.create(
        audition_request: audition_request,
        question: question,
        value: "My answer text"
      )

      expect(answer.value).to eq("My answer text")
      expect(answer.question).to eq(question)
      expect(answer.audition_request).to eq(audition_request)
    end
  end

  describe "answer types" do
    let(:audition_request) { create(:audition_request) }

    it "can store short text answers" do
      question = create(:question, question_type: "short_text", questionable: audition_request.call_to_audition)
      answer = create(:answer, question: question, audition_request: audition_request, value: "Short answer")

      expect(answer.value).to eq("Short answer")
    end

    it "can store long text answers" do
      question = create(:question, :long_text, questionable: audition_request.call_to_audition)
      answer = create(:answer, question: question, audition_request: audition_request, value: "This is a much longer answer with multiple sentences.")

      expect(answer.value).to eq("This is a much longer answer with multiple sentences.")
    end
  end
end
