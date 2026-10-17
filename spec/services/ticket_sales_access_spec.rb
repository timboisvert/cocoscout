# frozen_string_literal: true

require "rails_helper"

# Who sees a date's ticket sales, and how much (TicketSalesAccess levels):
# shares and contractors in full; the production team by role and the cast
# by the box office's Who sees sales; and a production team manager's comp
# allowance by the comp rules (CompRules).
RSpec.describe TicketSalesAccess do
  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true) } }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30)) }
  let(:listing) { create(:ticket_listing, organization: org, show: show) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 3_000, quantity: 80) }

  before { profile }

  def team_member(role, on: production)
    user = create(:user)
    create(:organization_role, user: user, organization: org, company_role: "member")
    ProductionPermission.create!(user: user, production: on, role: role)
    user
  end

  def performer(in_pool: true, cast_in: nil)
    user = create(:user)
    person = create(:person, user: user)
    user.update!(default_person: person)
    TalentPoolMembership.create!(talent_pool: production.effective_talent_pool, member: person) if in_pool
    if cast_in
      create(:show_person_role_assignment, show: cast_in, assignable: person, role: create(:role, production: cast_in.production))
      cast_in.update!(casting_finalized_at: Time.current)
    end
    user
  end

  def guest(quantity = 1)
    TicketComps::Guest.new(name: "Guest #{SecureRandom.hex(2)}", email: nil, tier: general, quantity: quantity)
  end

  # A listing that hasn't cached the rules from before a settings change
  # (a request loads its own; the spec's instance would remember).
  def fresh_listing
    TicketListing.find(listing.id)
  end

  describe ".level_for" do
    it "gives a production team manager everything by default, the numbers or nothing by the setting" do
      manager = team_member("manager")
      expect(described_class.level_for(manager, listing)).to eq(:full)
      expect(described_class.team_level_for(manager, production)).to eq(:full)
      profile.update!(team_manager_sales: "numbers")
      expect(described_class.level_for(manager, listing)).to eq(:numbers)
      profile.update!(team_manager_sales: "nothing")
      expect(described_class.level_for(manager, listing)).to be_nil
      expect(described_class.team_level_for(manager, production)).to be_nil
    end

    it "gives a production team viewer the numbers, and an organization viewer the same on every production" do
      viewer = team_member("viewer")
      org_viewer = create(:user)
      create(:organization_role, user: org_viewer, organization: org, company_role: "viewer")
      expect(described_class.level_for(viewer, listing)).to eq(:numbers)
      expect(described_class.level_for(org_viewer, listing)).to eq(:numbers)

      profile.update!(team_viewer_sales: "nothing")
      expect(described_class.level_for(viewer, listing)).to be_nil
      expect(described_class.level_for(org_viewer, listing)).to be_nil
    end

    it "leaves the organization's managers to the module, not to the team settings" do
      expect(described_class.team_level_for(owner, production)).to be_nil
      expect(described_class.comp_allowance(owner, listing)).to be_nil
    end

    it "gives the cast the numbers: everyone on the production, or only the people cast in the date" do
      in_pool = performer(in_pool: true)
      on_date = performer(in_pool: false, cast_in: show)
      stranger = create(:user)
      expect(described_class.level_for(in_pool, listing)).to eq(:numbers)
      expect(described_class.level_for(on_date, listing)).to eq(:numbers)
      expect(described_class.level_for(stranger, listing)).to be_nil

      # Cast in another date of the production, not in its pool: on the production, not on this date.
      other_date = create(:show, production: production, date_and_time: 12.days.from_now)
      elsewhere = performer(in_pool: false, cast_in: other_date)
      expect(described_class.level_for(elsewhere, listing)).to eq(:numbers)

      profile.update!(cast_sales: "show_cast")
      expect(described_class.level_for(in_pool, listing)).to be_nil
      expect(described_class.level_for(on_date, listing)).to eq(:numbers)
      expect(described_class.level_for(elsewhere, listing)).to be_nil

      profile.update!(cast_sales: "nothing")
      expect(described_class.level_for(on_date, listing)).to be_nil
    end

    it "reaches the cast through a shared talent pool, and through a group" do
      other = create(:production, organization: org, name: "Late Night Riot")
      TalentPoolShare.create!(production: other, talent_pool: production.talent_pools.first)
      other_listing = create(:ticket_listing, organization: org, show: create(:show, production: other, date_and_time: 6.days.from_now))
      member = performer(in_pool: true)
      expect(described_class.level_for(member, other_listing)).to eq(:numbers)

      grouped = create(:user)
      grouped_person = create(:person, user: grouped)
      group = create(:group)
      create(:group_membership, group: group, person: grouped_person)
      TalentPoolMembership.create!(talent_pool: production.effective_talent_pool, member: group)
      expect(described_class.level_for(grouped, listing)).to eq(:numbers)
    end

    it "gives a share and a contractor everything, whatever the settings say" do
      profile.update!(team_manager_sales: "nothing", cast_sales: "nothing")
      shared = create(:user)
      org.ticket_sales_viewers.create!(user: shared, scope: listing, granted_by: owner)
      expect(described_class.level_for(shared, listing)).to eq(:full)
      expect(described_class.levels_for(shared, [ listing ])).to eq(listing.id => :full)
    end

    it "shows nothing without Pro, with the box office closed, or for a draft or canceled date" do
      manager = team_member("manager")
      performer_user = performer(in_pool: true)
      listing.update!(status: "draft")
      expect(described_class.level_for(manager, listing)).to be_nil
      listing.update!(status: "canceled")
      expect(described_class.level_for(performer_user, listing)).to be_nil
      listing.update!(status: "on_sale")

      profile.update!(enabled: false)
      expect(described_class.level_for(manager, listing)).to be_nil
      expect(described_class.team_level_for(manager, production)).to be_nil
      profile.update!(enabled: true)

      org.update!(comped_indefinitely: false)
      expect(described_class.level_for(manager, listing)).to be_nil
      expect(described_class.level_for(performer_user, listing)).to be_nil
    end
  end

  describe ".comp_allowance" do
    let(:manager) { team_member("manager") }

    it "is for a production team manager at Everything only, while comps are on and the team may give some" do
      expect(described_class.comp_allowance(manager, listing)).to eq(date_left: nil, team_limit: nil, team_given: 0, left: nil)
      expect(described_class.can_comp?(manager, listing)).to be(true)
      expect(described_class.comp_allowance(team_member("viewer"), listing)).to be_nil
      expect(described_class.comp_allowance(performer, listing)).to be_nil

      profile.update!(team_manager_sales: "numbers")
      expect(described_class.comp_allowance(manager, listing)).to be_nil
      profile.update!(team_manager_sales: "everything", team_comps: false)
      expect(described_class.comp_allowance(manager, listing)).to be_nil
      profile.update!(team_comps: true, comps_enabled: false)
      expect(described_class.comp_allowance(manager, listing)).to be_nil
      expect(described_class.can_comp?(manager, listing)).to be(false)
    end

    # Tim, 2026-10-17: no comps for a show that's already started.
    it "is nil once the date has started" do
      show.update_columns(date_and_time: 1.hour.ago)
      expect(described_class.comp_allowance(manager, listing.reload)).to be_nil
    end

    it "counts the team's comps against a set number, within what the date has left" do
      profile.update!(team_comps_limit: "fixed", team_comps_per_show: 2)
      expect(described_class.comp_allowance(manager, listing)).to eq(date_left: nil, team_limit: 2, team_given: 0, left: 2)

      TicketComps.give!(listing, [ guest(1) ], by: manager, email_them: false)
      expect(described_class.comp_allowance(manager, listing)[:left]).to eq(1)

      # A manager's own comp isn't the team's.
      TicketComps.give!(listing, [ guest(1) ], by: owner, email_them: false)
      expect(described_class.comp_allowance(manager, listing)).to eq(date_left: nil, team_limit: 2, team_given: 1, left: 1)

      # The date's own limit caps it: 3 in all, 2 given, 1 left for anyone.
      profile.update!(comps_limit: "fixed", comps_per_show: 3)
      expect(described_class.comp_allowance(manager, fresh_listing)).to eq(date_left: 1, team_limit: 2, team_given: 1, left: 1)

      TicketComps.give!(fresh_listing, [ guest(1) ], by: manager, email_them: false)
      expect(described_class.comp_allowance(manager, fresh_listing)).to eq(date_left: 0, team_limit: 2, team_given: 2, left: 0)
      expect(described_class.can_comp?(manager, fresh_listing)).to be(false)
    end

    it "follows one per performer, and a production's or a date's own rules" do
      profile.update!(team_comps_limit: "per_performer")
      performer(in_pool: true, cast_in: show)
      performer(in_pool: true, cast_in: show)
      expect(described_class.comp_allowance(manager, fresh_listing)[:team_limit]).to eq(2)

      setup = ProductionTicketing.for(production)
      setup.update!(own_comps: true, comps_enabled: true, comps_limit: "unlimited", team_comps: true, team_comps_limit: "fixed", team_comps_per_show: 5)
      expect(fresh_listing.comp_rules_source).to eq(:production)
      expect(described_class.comp_allowance(manager, fresh_listing)).to eq(date_left: nil, team_limit: 5, team_given: 0, left: 5)

      fresh_listing.update!(own_comps: true, comps_enabled: false)
      expect(described_class.comp_allowance(manager, fresh_listing)).to be_nil
    end
  end

  describe "the comp rules everywhere comps are given" do
    it "refuses comps when they're off, and past the date's limit, from the Comps modal and the door alike" do
      listing.update!(own_comps: true, comps_enabled: false)
      expect { TicketComps.give!(listing, [ guest(1) ], by: owner, email_them: false) }.to raise_error(TicketComps::Error, "Comps are off for this show.")
      expect { TicketDoor.new(listing, owner).sell({ general.id.to_s => 1 }, kind: "comp") }.to raise_error(TicketCheckout::Error, "Comps are off for this show.")

      listing.update!(comps_enabled: true, comps_limit: "fixed", comps_per_show: 1)
      expect(listing.comps_left).to eq(1)
      expect { TicketComps.give!(listing, [ guest(2) ], by: owner, email_them: false) }.to raise_error(TicketComps::Error, "This date has 1 comp left to give.")
      TicketComps.give!(listing, [ guest(1) ], by: owner, email_them: false)
      expect(listing.comps_left).to eq(0)
      expect { TicketComps.give!(listing, [ guest(1) ], by: owner, email_them: false) }.to raise_error(TicketComps::Error, "This date has no comps left to give.")
      expect { TicketDoor.new(listing, owner).sell({ general.id.to_s => 1 }, kind: "comp") }.to raise_error(TicketCheckout::Error, "This date has no comps left to give.")
      # Cash at the door is untouched.
      expect(TicketDoor.new(listing, owner).sell({ general.id.to_s => 1 }, kind: "cash").channel).to eq("door_cash")
    end
  end
end
