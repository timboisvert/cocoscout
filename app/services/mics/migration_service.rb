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

    def initialize(mic:, user:)
      @mic  = mic
      @user = user
    end

    def call
      raise "Already migrated" if @mic.production_id
      raise "Missing user" unless @user
      raise "Mic must have a host venue" unless @mic.venue

      Mic.transaction do
        org           = ensure_organization
        production    = create_production(org)
        shows         = generate_shows(production)
        sign_up_form  = create_sign_up_form(production)
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
      managed = OrganizationRole.where(user: @user, company_role: "manager").first&.organization
      return managed if managed

      Organization.create!(name: "#{@user.email_address.split("@").first.titleize} Productions", owner: @user).tap do |org|
        OrganizationRole.create!(user: @user, organization: org, company_role: "manager")
      end
    end

    def create_production(org)
      org.productions.create!(
        name: @mic.name,
        description: @mic.blurb.presence,
        contact_email: @user.email_address
      )
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
          duration_minutes: @mic.spot_length_minutes && @mic.signup_cap ? @mic.spot_length_minutes * @mic.signup_cap : 120,
          # The venue is public; we don't have a Location for it. Mark
          # online so the Show validation passes — the real venue is on
          # the Mic record.
          is_online: true,
          online_location_info: @mic.venue.full_address.presence || @mic.venue.name
        )
      end
      out
    end

    def create_sign_up_form(production)
      production.sign_up_forms.create!(
        name: "#{@mic.name} sign-up",
        scope: "repeated",
        event_matching: "event_types",
        event_type_filter: [ "open_mic" ],
        active: true
      )
    end
  end
end
