require 'rails_helper'

RSpec.describe Production, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      production = build(:production)
      expect(production).to be_valid
    end

    it "is invalid without a name" do
      production = build(:production, name: nil)
      expect(production).not_to be_valid
      expect(production.errors[:name]).to include("can't be blank")
    end

    it "validates email format for contact_email" do
      production = build(:production, contact_email: "invalid_email")
      expect(production).not_to be_valid
      expect(production.errors[:contact_email]).to be_present
    end

    it "allows blank contact_email" do
      production = build(:production, contact_email: "")
      expect(production).to be_valid
    end

    it "normalizes contact_email to lowercase and strips whitespace" do
      production = create(:production, contact_email: "  CONTACT@EXAMPLE.COM  ")
      expect(production.contact_email).to eq("contact@example.com")
    end
  end

  describe "associations" do
    it "belongs to production_company" do
      production = create(:production)
      expect(production.production_company).to be_present
      expect(production).to respond_to(:production_company)
    end

    it "has many shows" do
      production = create(:production)
      expect(production).to respond_to(:shows)
    end

    it "has many audition_cycles" do
      production = create(:production)
      expect(production).to respond_to(:audition_cycles)
    end

    it "has many roles" do
      production = create(:production)
      expect(production).to respond_to(:roles)
    end
  end

  describe "#initials" do
    it "returns initials for a single word name" do
      production = create(:production, name: "Hamilton")
      expect(production.initials).to eq("H")
    end

    it "returns initials for a multi-word name" do
      production = create(:production, name: "The Lion King")
      expect(production.initials).to eq("TLK")
    end

    it "returns uppercase initials" do
      production = create(:production, name: "wicked")
      expect(production.initials).to eq("W")
    end

    it "returns empty string for blank name" do
      production = build(:production, name: "")
      expect(production.initials).to eq("")
    end

    it "handles names with extra spaces" do
      production = create(:production, name: "West  Side  Story")
      expect(production.initials).to eq("WSS")
    end
  end

  describe "#next_show" do
    let(:production) { create(:production) }

    it "returns the next upcoming show" do
      create(:show, production: production, date_and_time: 1.week.ago)
      next_show = create(:show, production: production, date_and_time: 1.day.from_now)
      create(:show, production: production, date_and_time: 1.week.from_now)

      expect(production.next_show).to eq(next_show)
    end

    it "returns nil when there are no future shows" do
      create(:show, production: production, date_and_time: 1.week.ago)

      expect(production.next_show).to be_nil
    end

    it "ignores shows in the past" do
      create(:show, production: production, date_and_time: 2.weeks.ago)
      create(:show, production: production, date_and_time: 1.week.ago)
      next_show = create(:show, production: production, date_and_time: 1.day.from_now)

      expect(production.next_show).to eq(next_show)
    end
  end

  describe "logo attachment" do
    it "can have a logo attached" do
      production = create(:production)
      production.logo.attach(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.png')),
        filename: 'logo.png',
        content_type: 'image/png'
      )

      expect(production.logo).to be_attached
    end
  end

  describe "dependent destroy behavior" do
    let(:production) { create(:production) }

    it "destroys associated shows when destroyed" do
      create(:show, production: production)
      create(:show, production: production)

      expect { production.destroy }.to change { Show.count }.by(-2)
    end

    it "destroys associated roles when destroyed" do
      create(:role, production: production)

      expect { production.destroy }.to change { Role.count }.by(-1)
    end
  end
end
