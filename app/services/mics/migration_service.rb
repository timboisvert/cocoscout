# frozen_string_literal: true

# Mic → Production migration. Given a Mic and a user who has producer
# rights on it, materialize an Organization (if needed), a Production,
# six months of weekly open-mic Shows, a SignUpForm with
# `event_type_filter: ["open_mic"]`, and link `Mic.production_id`. All or
# nothing in a single transaction.
module Mics
  class MigrationService
    HORIZON_MONTHS = 6

    Result = Struct.new(:mic, :production, :organization, :sign_up_form, :shows, keyword_init: true)

    # Organizations this user can migrate into — owns or has a manager role.
    def self.organizations_for(user)
      ids = []
      ids += Organization.where(owner_id: user.id).pluck(:id)
      ids += OrganizationRole.where(user_id: user.id, company_role: "manager").pluck(:organization_id)
      Organization.where(id: ids.uniq).order(:name)
    end

    def self.user_manages?(user, org)
      return false unless user && org
      org.owner_id == user.id ||
        OrganizationRole.where(user_id: user.id, organization_id: org.id, company_role: "manager").exists?
    end

    # Options:
    #   organization_id     → reuse this org (must be owned/managed by user)
    #   new_organization_name → create a new org with this name
    #   production_id       → reuse this production (must belong to chosen org)
    #   production_name     → name override when creating a new production
    def initialize(mic:, user:, organization_id: nil, new_organization_name: nil,
                   production_id: nil, production_name: nil, signup_form_defaults: {})
      @mic = mic
      @user = user
      @organization_id = organization_id.presence
      @new_organization_name = new_organization_name.presence
      @production_id = production_id.presence
      @production_name = production_name.presence
      @signup_form_defaults = (signup_form_defaults || {}).to_h.symbolize_keys
    end

    def call
      raise "Already migrated" if @mic.production_id
      raise "Missing user" unless @user
      raise "Mic must have a host venue" unless @mic.venue

      Mic.transaction do
        org           = ensure_organization
        production    = ensure_production(org)
        shows         = generate_shows(production)
        sign_up_form  = ensure_sign_up_form(production)
        @mic.update!(production_id: production.id, claimed_at: @mic.claimed_at || Time.current)
        @mic.mic_edits.create!(editor_user_id: @user.id, source: :migration,
                                field: "production_id", new_value: production.id.to_s,
                                note: "Migrated via Mics::MigrationService")
        Result.new(mic: @mic, production: production, organization: org,
                   sign_up_form: sign_up_form, shows: shows)
      end
    end

    private

    def ensure_organization
      if @organization_id
        org = Organization.find(@organization_id)
        unless self.class.user_manages?(@user, org)
          raise "You don't have manager access to that organization."
        end
        return org
      end

      name = @new_organization_name.presence || default_org_name
      Organization.create!(name: name, owner: @user).tap do |org|
        OrganizationRole.create!(user: @user, organization: org, company_role: "manager")
      end
    end

    def ensure_production(org)
      if @production_id
        production = org.productions.find_by(id: @production_id)
        raise "That production isn't in the chosen organization." unless production
        production
      else
        org.productions.create!(
          name: @production_name.presence || @mic.name,
          description: @mic.blurb.presence,
          contact_email: @user.email_address
        )
      end
    end

    def default_org_name
      base = @user.email_address.split("@").first.titleize
      "#{base} Productions"
    end

    def ensure_sign_up_form(production)
      production.sign_up_forms.detect { |f| f.active && Array(f.event_type_filter).include?("open_mic") } ||
        create_sign_up_form(production)
    end

    def generate_shows(production)
      occs = @mic.next_occurrences(limit: 200) # cap; we'll trim by horizon
      horizon = HORIZON_MONTHS.months.from_now
      group_id = SecureRandom.uuid
      out = []
      occs.each do |occ|
        starts = occ[:starts_at]
        break if starts > horizon
        out << production.shows.create!(
          date_and_time: starts,
          event_type: :open_mic,
          recurrence_group_id: group_id,
          duration_minutes: estimated_duration_minutes,
          # The venue is public; we don't have a Location for it. Mark
          # online so the Show validation passes — the real venue is on
          # the Mic record.
          is_online: true,
          online_location_info: @mic.venue.full_address.presence || @mic.venue.name
        )
      end
      out
    end

    # Both `signup_cap` and `spot_length_minutes` are free text now
    # ("10ish", "3-5 minutes"). Pull the first integer out of each for
    # show-duration estimation; fall back to 120 if we can't parse a
    # sensible product.
    def estimated_duration_minutes
      cap_int  = @mic.signup_cap.to_s.scan(/\d+/).first&.to_i
      spot_int = @mic.spot_length_minutes.to_s.scan(/\d+/).first&.to_i
      if spot_int && spot_int.positive? && cap_int && cap_int.positive?
        spot_int * cap_int
      else
        120
      end
    end

    def create_sign_up_form(production)
      attrs = {
        name: "#{@mic.name} sign-up",
        scope: "repeated",
        event_matching: "event_types",
        event_type_filter: [ "open_mic" ],
        active: true
      }

      # Apply the producer's Step 4 starting settings. Skip blanks so we
      # don't clobber the column defaults with nils.
      opens_days = @signup_form_defaults[:opens_days_before].to_s
      attrs[:opens_days_before] = opens_days.to_i if opens_days.match?(/\A\d+\z/)

      slot_count = @signup_form_defaults[:slot_count].to_s
      attrs[:slot_count] = slot_count.to_i if slot_count.match?(/\A\d+\z/) && slot_count.to_i.positive?

      slot_minutes = @signup_form_defaults[:slot_interval_minutes].to_s
      attrs[:slot_interval_minutes] = slot_minutes.to_i if slot_minutes.match?(/\A\d+\z/) && slot_minutes.to_i.positive?

      instructions = @signup_form_defaults[:instruction_text].to_s.strip
      attrs[:instruction_text] = instructions if instructions.present?

      production.sign_up_forms.create!(attrs)
    end
  end
end
