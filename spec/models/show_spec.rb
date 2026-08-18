# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Show, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      show = build(:show)
      expect(show).to be_valid
    end

    it 'is invalid without a location or is_online' do
      show = build(:show, location: nil, is_online: false)
      expect(show).not_to be_valid
      expect(show.errors[:base]).to include('Please select a location or mark this event as online')
    end

    it 'is valid when is_online is true and location is nil' do
      show = build(:show, location: nil, is_online: true)
      expect(show).to be_valid
    end

    it 'is invalid without an event_type' do
      show = build(:show, event_type: nil)
      expect(show).not_to be_valid
      expect(show.errors[:event_type]).to include("can't be blank")
    end
  end

  describe 'associations' do
    it 'belongs to production' do
      show = create(:show)
      expect(show.production).to be_present
      expect(show).to respond_to(:production)
    end

    it 'belongs to location' do
      show = create(:show)
      expect(show.location).to be_present
      expect(show).to respond_to(:location)
    end

    it 'has many show_person_role_assignments' do
      show = create(:show)
      expect(show).to respond_to(:show_person_role_assignments)
    end

    it 'has many people through show_person_role_assignments' do
      show = create(:show)
      expect(show).to respond_to(:people)
    end

    it 'has many roles through show_person_role_assignments' do
      show = create(:show)
      expect(show).to respond_to(:roles)
    end

    it 'has many show_links' do
      show = create(:show)
      expect(show).to respond_to(:show_links)
    end

    it 'has many show_availabilities' do
      show = create(:show)
      expect(show).to respond_to(:show_availabilities)
    end

    it 'has many available_people through show_availabilities' do
      show = create(:show)
      expect(show).to respond_to(:available_people)
    end
  end

  describe 'event_type enum' do
    it 'can be a show' do
      show = create(:show, event_type: :show)
      expect(show.event_type).to eq('show')
      expect(show.show?).to be true
    end

    it 'can be a rehearsal' do
      show = create(:show, :rehearsal)
      expect(show.event_type).to eq('rehearsal')
      expect(show.rehearsal?).to be true
    end

    it 'can be a meeting' do
      show = create(:show, :meeting)
      expect(show.event_type).to eq('meeting')
      expect(show.meeting?).to be true
    end
  end

  describe 'recurrence' do
    let(:recurrence_group_id) { SecureRandom.uuid }

    describe '#recurring?' do
      it 'returns true when recurrence_group_id is present' do
        show = create(:show, recurrence_group_id: recurrence_group_id)
        expect(show.recurring?).to be true
      end

      it 'returns false when recurrence_group_id is nil' do
        show = create(:show, recurrence_group_id: nil)
        expect(show.recurring?).to be false
      end
    end

    describe '#recurrence_siblings' do
      it 'returns other shows in the same recurrence group' do
        show1 = create(:show, recurrence_group_id: recurrence_group_id)
        show2 = create(:show, recurrence_group_id: recurrence_group_id)
        show3 = create(:show, recurrence_group_id: recurrence_group_id)
        other_show = create(:show)

        siblings = show1.recurrence_siblings
        expect(siblings).to include(show2, show3)
        expect(siblings).not_to include(show1, other_show)
      end

      it 'returns empty relation for non-recurring shows' do
        show = create(:show, recurrence_group_id: nil)
        expect(show.recurrence_siblings).to be_empty
      end
    end

    describe '#recurrence_group' do
      it 'returns all shows in the recurrence group including self' do
        show1 = create(:show, recurrence_group_id: recurrence_group_id)
        show2 = create(:show, recurrence_group_id: recurrence_group_id)
        show3 = create(:show, recurrence_group_id: recurrence_group_id)
        other_show = create(:show)

        group = show1.recurrence_group
        expect(group).to include(show1, show2, show3)
        expect(group).not_to include(other_show)
      end

      it 'returns empty relation for non-recurring shows' do
        show = create(:show, recurrence_group_id: nil)
        expect(show.recurrence_group).to be_empty
      end
    end
  end

  describe 'scopes' do
    describe '.in_recurrence_group' do
      it 'finds all shows with the specified recurrence_group_id' do
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

  describe 'poster attachment' do
    it 'can have a poster attached' do
      show = create(:show)
      show.poster.attach(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.png')),
        filename: 'poster.png',
        content_type: 'image/png'
      )

      expect(show.poster).to be_attached
    end
  end

  describe 'duration methods' do
    let(:show) { build(:show, date_and_time: Time.zone.parse('2025-03-15 19:00:00')) }

    describe '#ends_at' do
      it 'returns date_and_time plus duration_minutes when set' do
        show.duration_minutes = 180
        expect(show.ends_at).to eq(Time.zone.parse('2025-03-15 22:00:00'))
      end

      it 'uses default 120 minutes when duration_minutes is nil' do
        show.duration_minutes = nil
        expect(show.ends_at).to eq(Time.zone.parse('2025-03-15 21:00:00'))
      end
    end

    describe '#duration_hours' do
      it 'returns duration in hours when set' do
        show.duration_minutes = 90
        expect(show.duration_hours).to eq(1.5)
      end

      it 'uses default 120 minutes when duration_minutes is nil' do
        show.duration_minutes = nil
        expect(show.duration_hours).to eq(2.0)
      end
    end

    describe '#time_range_display' do
      it 'returns formatted time range when duration is set' do
        show.duration_minutes = 120
        expect(show.time_range_display).to eq('7:00 PM – 9:00 PM')
      end

      it 'returns only start time when duration is nil' do
        show.duration_minutes = nil
        expect(show.time_range_display).to eq('7:00 PM')
      end

      it 'handles different durations correctly' do
        show.duration_minutes = 90
        expect(show.time_range_display).to eq('7:00 PM – 8:30 PM')
      end
    end
  end

  describe 'act-based lineups' do
    let(:production) { create(:production, casting_mode: 'act_based') }
    let(:show) { create(:show, production: production) }
    let!(:magic1) { create(:role, production: production, name: 'Magic', position: 1) }
    let!(:variety) { create(:role, production: production, name: 'Variety', position: 2) }
    let!(:intermission) { create(:role, production: production, name: 'Intermission', category: 'break', position: 3) }
    let!(:magic2) { create(:role, production: production, name: 'Magic', position: 4) }
    let(:dancer) { create(:person) }
    let(:duo) { create(:group) }

    it 'delegates the casting mode to the production' do
      expect(show).to be_act_based
      expect(create(:show)).to be_role_based
    end

    describe '#effective_casting_mode (per-show override, nil inherits)' do
      it 'inherits the production mode when nothing is set' do
        expect(show.casting_mode).to be_nil
        expect(show.effective_casting_mode).to eq('act_based')
        expect(show.uses_custom_casting_mode?).to be(false)
      end

      it 'lets one show in a role-based production cast by acts' do
        role_show = create(:show)
        role_show.update!(casting_mode: 'act_based')
        expect(role_show.effective_casting_mode).to eq('act_based')
        expect(role_show).to be_act_based
        expect(role_show.uses_custom_casting_mode?).to be(true)
        expect(role_show.production).to be_role_based
      end

      it 'lets one show in an act-based production cast by roles' do
        show.update!(casting_mode: 'role_based')
        expect(show).to be_role_based
        expect(show).not_to be_act_based
        expect(production).to be_act_based
      end

      it 'treats an empty string as "inherit"' do
        show.update!(casting_mode: 'role_based')
        show.update!(casting_mode: '')
        expect(show.reload.casting_mode).to be_nil
        expect(show).to be_act_based
      end

      it 'rejects an unknown mode' do
        show.casting_mode = 'vibes'
        expect(show).not_to be_valid
        expect(show.errors[:casting_mode]).to be_present
      end
    end

    describe '#casting_progress' do
      it 'does not count break markers as slots' do
        create(:show_person_role_assignment, show: show, role: magic1, assignable: dancer)

        expect(show.casting_progress).to include(total: 3, filled: 1)
        expect(show).not_to be_fully_cast
      end
    end

    describe '#lineup_act_counts' do
      it 'counts one act per assignment a performer holds, skipping breaks' do
        create(:show_person_role_assignment, show: show, role: magic1, assignable: dancer)
        create(:show_person_role_assignment, show: show, role: magic2, assignable: dancer)
        create(:show_person_role_assignment, show: show, role: variety, assignable: duo)

        expect(show.lineup_act_counts).to eq(
          ShowPayout.act_key(dancer) => 2,
          ShowPayout.act_key(duo) => 1
        )
      end

      it 'folds a guest holding two acts into one payee keyed by their first slot' do
        first = create(:show_person_role_assignment, show: show, role: magic1, assignable: nil, guest_name: 'Lola', guest_email: 'lola@example.com')
        create(:show_person_role_assignment, show: show, role: magic2, assignable: nil, guest_name: 'Lola L.', guest_email: 'LOLA@example.com')
        create(:show_person_role_assignment, show: show, role: variety, assignable: nil, guest_name: 'Rex')

        counts = show.lineup_act_counts
        expect(counts[ShowPayout.act_key(first)]).to eq(2)
        expect(counts.values.sum).to eq(3)
        expect(counts.size).to eq(2)
      end
    end

    context 'with show roles alongside the lineup' do
      let!(:mc) { create(:role, production: production, name: 'MC', standing: true, position: 0) }
      let!(:kittens) { create(:role, production: production, name: 'Stage Kitten', standing: true, quantity: 2, position: 5) }

      it "doesn't count a show role as an act" do
        create(:show_person_role_assignment, show: show, role: mc, assignable: dancer)
        create(:show_person_role_assignment, show: show, role: magic1, assignable: dancer)
        create(:show_person_role_assignment, show: show, role: kittens, assignable: duo)

        expect(show.lineup_act_counts).to eq(ShowPayout.act_key(dancer) => 1)
      end

      it 'lists the show roles each payee holds, by name' do
        create(:show_person_role_assignment, show: show, role: mc, assignable: dancer)
        create(:show_person_role_assignment, show: show, role: magic1, assignable: dancer)
        create(:show_person_role_assignment, show: show, role: kittens, assignable: duo)
        create(:show_person_role_assignment, show: show, role: variety, assignable: create(:person))

        expect(show.show_role_names_by_payee).to eq(
          ShowPayout.act_key(dancer) => [ 'MC' ],
          ShowPayout.act_key(duo) => [ 'Stage Kitten' ]
        )
      end

      it 'keys a guest by their first assignment even when that is a show role' do
        first = create(:show_person_role_assignment, show: show, role: mc, assignable: nil, guest_name: 'Lola')
        create(:show_person_role_assignment, show: show, role: magic1, assignable: nil, guest_name: 'Lola')
        create(:show_person_role_assignment, show: show, role: magic2, assignable: nil, guest_name: 'lola')

        key = ShowPayout.act_key(first)
        expect(show.lineup_act_counts).to eq(key => 2)
        expect(show.show_role_names_by_payee).to eq(key => [ 'MC' ])
        expect(show.pay_cast_assignments[:guests].map(&:id)).to eq([ first.id ])
      end

      it 'copies the flag onto an act-based custom lineup and drops it for a role-based night' do
        show.copy_roles_from_production!
        expect(show.custom_roles.find_by(name: 'MC')).to be_standing
        expect(show.custom_roles.find_by(name: 'Stage Kitten').quantity).to eq(2)

        role_night = create(:show, production: production, casting_mode: 'role_based')
        role_night.copy_roles_from_production!
        expect(role_night.custom_roles.find_by(name: 'MC')).not_to be_standing
      end
    end

    describe '#pay_cast_assignments' do
      it 'lists people once and collapses guests in an act-based production' do
        create(:show_person_role_assignment, show: show, role: magic1, assignable: dancer)
        create(:show_person_role_assignment, show: show, role: magic2, assignable: dancer)
        create(:show_person_role_assignment, show: show, role: magic1, assignable: nil, guest_name: 'Lola')
        create(:show_person_role_assignment, show: show, role: magic2, assignable: nil, guest_name: 'lola')

        cast = show.pay_cast_assignments
        expect(cast[:people]).to eq([ dancer ])
        expect(cast[:guests].size).to eq(1)
      end

      it 'keeps each guest slot separate in a role-based production' do
        role_show = create(:show)
        host = create(:role, production: role_show.production, name: 'Host')
        mc = create(:role, production: role_show.production, name: 'MC')
        create(:show_person_role_assignment, show: role_show, role: host, assignable: nil, guest_name: 'Lola')
        create(:show_person_role_assignment, show: role_show, role: mc, assignable: nil, guest_name: 'Lola')

        expect(role_show.pay_cast_assignments[:guests].size).to eq(2)
      end
    end

    describe '#copy_roles_from_production! (copies in the show\'s own shape)' do
      let!(:magic3) { create(:role, production: production, name: 'Magic', position: 5) }

      it 'copies an act-based show\'s lineup as is, break included, and says which copy came from which' do
        copied_from = show.copy_roles_from_production!

        copies = show.custom_roles.reload
        expect(copies.map { |r| [ r.name, r.category, r.quantity ] })
          .to eq([ [ 'Magic', 'performing', 1 ], [ 'Variety', 'performing', 1 ], [ 'Intermission', 'break', 1 ], [ 'Magic', 'performing', 1 ], [ 'Magic', 'performing', 1 ] ])
        expect(copied_from.keys).to eq([ magic1.id, variety.id, intermission.id, magic2.id, magic3.id ])
        expect(copied_from.values.map(&:id)).to eq(copies.map(&:id))
      end

      it 'copies role-shaped for a show pinned to roles: adjacent same-named acts fold into one role, breaks go, other repeats get a suffix' do
        show.update!(casting_mode: 'role_based')

        copied_from = nil
        expect { copied_from = show.copy_roles_from_production! }.not_to raise_error

        copies = show.custom_roles.reload
        expect(copies.map { |r| [ r.name, r.quantity, r.position ] }).to eq([ [ 'Magic', 1, 0 ], [ 'Variety', 1, 1 ], [ 'Magic (2)', 2, 2 ] ])
        expect(copies).to all(be_valid)
        expect(copied_from[magic1.id]).to eq(copies[0])
        expect(copied_from[variety.id]).to eq(copies[1])
        expect(copied_from[magic2.id]).to eq(copies[2])
        expect(copied_from[magic3.id]).to eq(copies[2])
        expect(copied_from).not_to have_key(intermission.id)
      end

      it 'copies a role-based production\'s roles unchanged' do
        role_show = create(:show)
        host = create(:role, production: role_show.production, name: 'Host', quantity: 2, position: 3)
        mc = create(:role, production: role_show.production, name: 'MC', position: 7)

        copied_from = role_show.copy_roles_from_production!

        expect(role_show.custom_roles.reload.map { |r| [ r.name, r.quantity ] }).to eq([ [ 'Host', 2 ], [ 'MC', 1 ] ])
        expect(copied_from.keys).to eq([ host.id, mc.id ])
      end
    end
  end
end
