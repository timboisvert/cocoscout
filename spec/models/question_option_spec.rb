require 'rails_helper'

RSpec.describe QuestionOption, type: :model do
  describe "associations" do
    it "belongs to question" do
      option = create(:question_option)
      expect(option.question).to be_present
      expect(option).to respond_to(:question)
    end
  end

  describe "creating options" do
    it "can be created with text" do
      question = create(:question, :multiple_choice)
      option = QuestionOption.create(question: question, text: "Option A")

      expect(option.text).to eq("Option A")
      expect(option.question).to eq(question)
    end

    it "can belong to a multiple choice question" do
      question = create(:question, :multiple_choice)
      option1 = create(:question_option, question: question, text: "Red")
      option2 = create(:question_option, question: question, text: "Blue")
      option3 = create(:question_option, question: question, text: "Green")

      expect(question.question_options).to include(option1, option2, option3)
      expect(question.question_options.count).to eq(3)
    end
  end
end
