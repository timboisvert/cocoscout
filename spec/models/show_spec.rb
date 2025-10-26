require 'rails_helper'

RSpec.describe Show, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      show = build(:show)
      expect(show).to be_valid
    end

    it "is invalid without a location" do
      show = build(:show, location: nil)
      expect(show).not_to be_valid
      expect(show.errors[:location]).to include("can't be blank")
    end

    it "is invalid without an event_type" do
      show = build(:show, event_type: nil)
      expect(show).not_to be_valid
      expect(show.errors[:event_type]).to include("can't be blank")
    end
  end

  describe "associations" do
    it "belongs to production" do
      show = create(:show)
      expect(show.production).to be_present
      expect(show).to respond_to(:production)
    end

    it "belongs to location" do
      show = create(:show)
      expect(show.location).to be_present
      expect(show).to respond_to(:location)
    end

    it "has many show_person_role_assignments" do
      show = create(:show)
      expect(show).to respond_to(:show_person_role_assignments)
    end

    it "has many people through show_person_role_assignments" do
      show = create(:show)
      expect(show).to respond_to(:people)
    end

    it "has many roles through show_person_role_assignments" do
      show = create(:show)
      expect(show).to respond_to(:roles)
    end

    it "has many show_links" do
      show = create(:show)
      expect(show).to respond_to(:show_links)
    end

    it "has many show_availabilities" do
      show = create(:show)
      expect(show).to respond_to(:show_availabilities)
    end

    it "has many available_people through show_availabilities" do
      show = create(:show)
      expect(show).to respond_to(:available_people)
    end
  end

  describe "event_type enum" do
    it "can be a show" do
      show = create(:show, event_type: :show)
      expect(show.event_type).to eq("show")
      expect(show.show?).to be true
    end

    it "can be a rehearsal" do
      show = create(:show, :rehearsal)
      expect(show.event_type).to eq("rehearsal")
      expect(show.rehearsal?).to be true
    end

    it "can be a meeting" do
      show = create(:show, :meeting)
      expect(show.event_type).to eq("meeting")
      expect(show.meeting?).to be true
    end
  end

  describe "recurrence" do
    let(:recurrence_group_id) { SecureRandom.uuid }

    describe "#recurring?" do
      it "returns true when recurrence_group_id is present" do
        show = create(:show, recurrence_group_id: recurrence_group_id)
        expect(show.recurring?).to be true
      end

      it "returns false when recurrence_group_id is nil" do
        show = create(:show, recurrence_group_id: nil)
        expect(show.recurring?).to be false
      end
    end

    describe "#recurrence_siblings" do
      it "returns other shows in the same recurrence group" do
        show1 = create(:show, recurrence_group_id: recurrence_group_id)
        show2 = create(:show, recurrence_group_id: recurrence_group_id)
        show3 = create(:show, recurrence_group_id: recurrence_group_id)
        other_show = create(:show)

        siblings = show1.recurrence_siblings
        expect(siblings).to include(show2, show3)
        expect(siblings).not_to include(show1, other_show)
      end

      it "returns empty relation for non-recurring shows" do
        show = create(:show, recurrence_group_id: nil)
        expect(show.recurrence_siblings).to be_empty
      end
    end

    describe "#recurrence_group" do
      it "returns all shows in the recurrence group including self" do
        show1 = create(:show, recurrence_group_id: recurrence_group_id)
        show2 = create(:show, recurrence_group_id: recurrence_group_id)
        show3 = create(:show, recurrence_group_id: recurrence_group_id)
        other_show = create(:show)

        group = show1.recurrence_group
        expect(group).to include(show1, show2, show3)
        expect(group).not_to include(other_show)
      end

      it "returns empty relation for non-recurring shows" do
        show = create(:show, recurrence_group_id: nil)
        expect(show.recurrence_group).to be_empty
      end
    end
  end

  describe "scopes" do
    describe ".in_recurrence_group" do
      it "finds all shows with the specified recurrence_group_id" do
        recurrence_group_id = SecureRandom.uuid
        show1 = create(:show, recurrence_group_id: recurrence_group_id)
        show2 = create(:show, recurrence_group_id: recurrence_group_id)
        other_show = create(:show)

        shows = Show.in_recurrence_group(recurrence_group_id)
        expect(shows).to include(show1, show2)
        expect(shows).not_to include(other_show)
      end
    end
  end

  describe "poster attachment" do
    it "can have a poster attached" do
      show = create(:show)
      show.poster.attach(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.png')),
        filename: 'poster.png',
        content_type: 'image/png'
      )

      expect(show.poster).to be_attached
    end
  end
end
