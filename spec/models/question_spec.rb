require 'rails_helper'

RSpec.describe Question, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      question = build(:question)
      expect(question).to be_valid
    end

    it "is invalid without text" do
      question = build(:question, text: nil)
      expect(question).not_to be_valid
      expect(question.errors[:text]).to include("can't be blank")
    end

    it "is invalid without question_type" do
      question = build(:question, question_type: nil)
      expect(question).not_to be_valid
      expect(question.errors[:question_type]).to include("can't be blank")
    end
  end

  describe "associations" do
    it "belongs to questionable" do
      question = create(:question)
      expect(question.questionable).to be_present
      expect(question).to respond_to(:questionable)
    end

    it "has many question_options" do
      question = create(:question)
      expect(question).to respond_to(:question_options)
    end

    it "has many answers" do
      question = create(:question)
      expect(question).to respond_to(:answers)
    end
  end

  describe "nested attributes" do
    it "accepts nested attributes for question_options" do
      call_to_audition = create(:call_to_audition)
      question = call_to_audition.questions.create(
        text: "What is your favorite color?",
        question_type: "multiple_choice",
        question_options_attributes: [
          { text: "Red" },
          { text: "Blue" },
          { text: "Green" }
        ]
      )

      expect(question.question_options.count).to eq(3)
      expect(question.question_options.pluck(:text)).to match_array([ "Red", "Blue", "Green" ])
    end

    it "allows destroying question_options" do
      question = create(:question, :multiple_choice)
      option = create(:question_option, question: question)

      question.update(question_options_attributes: [ { id: option.id, _destroy: true } ])

      expect(question.question_options.count).to eq(0)
    end
  end

  describe "required field" do
    it "can be set to required" do
      question = create(:question, :required)
      expect(question.required).to be true
    end

    it "defaults to not required" do
      question = create(:question)
      expect(question.required).to be false
    end
  end

  describe "question types" do
    it "can be short_text" do
      question = create(:question, question_type: "short_text")
      expect(question.question_type).to eq("short_text")
    end

    it "can be long_text" do
      question = create(:question, :long_text)
      expect(question.question_type).to eq("long_text")
    end

    it "can be multiple_choice" do
      question = create(:question, :multiple_choice)
      expect(question.question_type).to eq("multiple_choice")
    end
  end

  describe "polymorphic questionable" do
    it "can belong to a CallToAudition" do
      call_to_audition = create(:call_to_audition)
      question = create(:question, questionable: call_to_audition)

      expect(question.questionable).to eq(call_to_audition)
      expect(question.questionable_type).to eq("CallToAudition")
    end
  end
end
