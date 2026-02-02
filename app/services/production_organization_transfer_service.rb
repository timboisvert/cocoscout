# frozen_string_literal: true

# Service to transfer a Production from one Organization to another.
# This is a complex operation with many cascading effects.
#
# Usage:
#   result = ProductionOrganizationTransferService.analyze(production, target_org)
#   result = ProductionOrganizationTransferService.execute(production, target_org)
#
class ProductionOrganizationTransferService
  class TransferError < StandardError; end

  attr_reader :production, :source_org, :target_org, :analysis, :changes_made, :location_mappings

  def initialize(production, target_org, location_mappings: {})
    @production = production
    @source_org = production.organization
    @target_org = target_org
    @location_mappings = location_mappings # { source_location_id => target_location_id }
    @analysis = {}
    @changes_made = []
  end

  # Class method for analysis
  def self.analyze(production, target_org)
    new(production, target_org).analyze
  end

  # Class method for execution
  # location_mappings: { source_location_id => target_location_id }
  def self.execute(production, target_org, location_mappings: {})
    new(production, target_org, location_mappings: location_mappings).execute
  end

  # Analyzes what will happen when transferring this production
  # Returns a hash with warnings and counts of affected records
  def analyze
    @analysis = {
      source_org: { id: source_org.id, name: source_org.name },
      target_org: { id: target_org.id, name: target_org.name },
      production: { id: production.id, name: production.name },
      warnings: [],
      data_loss: [],
      migrations: [],
      location_analysis: nil # Will be populated if shows have locations
    }

    # Validate basic requirements
    validate_transfer!

    # Analyze each category of data
    analyze_shows_and_locations
    analyze_talent_pool_and_people
    analyze_permissions_and_team
    analyze_messages
    analyze_financial_data
    analyze_ticketing
    analyze_casting_tables
    analyze_contracts

    @analysis
  end

  # Executes the transfer within a transaction
  def execute
    analyze # Run analysis first

    ActiveRecord::Base.transaction do
      # 1. Break external connections
      break_ticketing_connections
      break_contract_connections
      break_casting_table_connections
      break_payroll_connections

      # 2. Handle permissions (must delete before org change)
      clear_production_permissions
      clear_team_invitations

      # 3. Handle talent pool directory gap
      migrate_talent_pool_members_to_target_org
      break_talent_pool_shares

      # 4. Apply location mappings (auto-match + user-provided)
      apply_location_mappings

      # 5. Update organization references on related records
      update_message_organization_references
      update_log_organization_references
      update_payroll_run_references

      # 6. Finally, move the production
      production.update!(organization_id: target_org.id)

      @changes_made << "Production #{production.name} transferred to #{target_org.name}"
    end

    { success: true, changes: @changes_made }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  private

  def validate_transfer!
    raise TransferError, "Source and target organization are the same" if source_org.id == target_org.id
    raise TransferError, "Target organization not found" unless target_org.present?
  end

  # === ANALYSIS METHODS ===

  def analyze_shows_and_locations
    shows_with_locations = production.shows.where.not(location_id: nil).includes(:location)

    if shows_with_locations.any?
      # Get unique source locations used by shows
      source_location_ids = shows_with_locations.pluck(:location_id).uniq
      source_locations = Location.where(id: source_location_ids).index_by(&:id)

      # Get target org locations for matching
      target_locations = target_org.locations.order(:name).to_a
      target_locations_by_name = target_locations.index_by { |l| l.name.downcase.strip }

      # Analyze each source location
      auto_matched = []
      needs_mapping = []

      source_locations.each do |id, source_loc|
        show_count = shows_with_locations.count { |s| s.location_id == id }
        target_match = target_locations_by_name[source_loc.name.downcase.strip]

        if target_match
          auto_matched << {
            source_id: id,
            source_name: source_loc.name,
            target_id: target_match.id,
            target_name: target_match.name,
            show_count: show_count
          }
        else
          needs_mapping << {
            source_id: id,
            source_name: source_loc.name,
            source_address: source_loc.full_address,
            space_count: source_loc.location_spaces.count,
            show_count: show_count
          }
        end
      end

      @analysis[:location_analysis] = {
        total_shows_with_locations: shows_with_locations.count,
        auto_matched: auto_matched,
        needs_mapping: needs_mapping,
        target_locations: target_locations.map { |l| { id: l.id, name: l.name } }
      }

      # Add warnings based on analysis
      if needs_mapping.any?
        unmapped_show_count = needs_mapping.sum { |l| l[:show_count] }
        @analysis[:warnings] << {
          category: "Locations",
          message: "#{needs_mapping.count} location(s) need mapping (#{unmapped_show_count} shows affected)",
          details: needs_mapping.map { |l| "#{l[:source_name]} (#{l[:show_count]} shows)" }
        }
      end

      if auto_matched.any?
        @analysis[:migrations] << {
          category: "Location Matches",
          count: auto_matched.count,
          action: "Will auto-map to matching locations in target org"
        }
      end
    end

    @analysis[:migrations] << {
      category: "Shows",
      count: production.shows.count,
      action: "Will move with production"
    }
  end

  def analyze_talent_pool_and_people
    talent_pool = production.talent_pool
    return unless talent_pool

    # People not in target org
    people_in_pool = talent_pool.people.to_a
    groups_in_pool = talent_pool.groups.to_a

    people_not_in_target = people_in_pool.reject { |p| target_org.people.include?(p) }
    groups_not_in_target = groups_in_pool.reject { |g| target_org.groups.include?(g) }

    if people_not_in_target.any?
      @analysis[:migrations] << {
        category: "People (Talent Pool)",
        count: people_not_in_target.count,
        action: "Will be added to target organization's directory"
      }
    end

    if groups_not_in_target.any?
      @analysis[:migrations] << {
        category: "Groups (Talent Pool)",
        count: groups_not_in_target.count,
        action: "Will be added to target organization's directory"
      }
    end

    # Talent pool shares
    outgoing_shares = production.talent_pool_shares
    incoming_shares = talent_pool.talent_pool_shares

    if outgoing_shares.any? || incoming_shares.any?
      total_shares = outgoing_shares.count + incoming_shares.count
      @analysis[:warnings] << {
        category: "Talent Pool Shares",
        message: "#{total_shares} talent pool shares will be broken",
        details: []
      }
      @analysis[:data_loss] << "Talent pool sharing arrangements (#{total_shares} shares)"
    end
  end

  def analyze_permissions_and_team
    permissions_count = production.production_permissions.count
    if permissions_count > 0
      @analysis[:warnings] << {
        category: "Production Permissions",
        message: "#{permissions_count} production manager/viewer permissions will be removed",
        details: production.production_permissions.includes(:user).map { |p| p.user.email_address }
      }
      @analysis[:data_loss] << "Production team access (#{permissions_count} permissions)"
    end

    invitations_count = production.team_invitations.count
    if invitations_count > 0
      @analysis[:warnings] << {
        category: "Team Invitations",
        message: "#{invitations_count} pending team invitations will be deleted",
        details: []
      }
      @analysis[:data_loss] << "Pending team invitations (#{invitations_count})"
    end
  end

  def analyze_messages
    message_count = Message.where(production: production).count
    if message_count > 0
      @analysis[:migrations] << {
        category: "Messages",
        count: message_count,
        action: "Organization reference will be updated to target"
      }
    end
  end

  def analyze_financial_data
    # Payroll schedule
    if production.payroll_schedule.present?
      @analysis[:warnings] << {
        category: "Payroll Schedule",
        message: "Production payroll schedule will be deleted",
        details: []
      }
      @analysis[:data_loss] << "Payroll schedule configuration"
    end

    # Payroll runs
    payroll_runs_count = production.payroll_runs.count
    if payroll_runs_count > 0
      @analysis[:migrations] << {
        category: "Payroll Runs",
        count: payroll_runs_count,
        action: "Historical payroll runs will be updated to target organization"
      }
    end

    # Check for org-level payout schemes in use
    org_level_payouts = ShowPayout.joins(:show)
                                  .where(shows: { production_id: production.id })
                                  .joins(:payout_scheme)
                                  .where(payout_schemes: { production_id: nil, organization_id: source_org.id })
    if org_level_payouts.any?
      @analysis[:warnings] << {
        category: "Payout Schemes",
        message: "#{org_level_payouts.count} show payouts use org-level schemes that will be unlinked",
        details: []
      }
      @analysis[:data_loss] << "Show payout scheme references (#{org_level_payouts.count})"
    end
  end

  def analyze_ticketing
    links_count = production.ticketing_production_links.count
    if links_count > 0
      @analysis[:warnings] << {
        category: "Ticketing Integration",
        message: "Ticketing provider links will be removed (#{links_count} connections)",
        details: production.ticketing_production_links.includes(:ticketing_provider).map { |l| l.ticketing_provider&.name }
      }
      @analysis[:data_loss] << "Ticketing provider integration (#{links_count} links)"
    end
  end

  def analyze_casting_tables
    casting_table_entries = CastingTableProduction.where(production: production)
    if casting_table_entries.any?
      @analysis[:warnings] << {
        category: "Casting Tables",
        message: "Production will be removed from #{casting_table_entries.count} casting table(s)",
        details: []
      }
    end
  end

  def analyze_contracts
    if production.contract_id.present?
      @analysis[:warnings] << {
        category: "Contract",
        message: "Contract linkage will be removed",
        details: [ production.contract&.name ]
      }
      @analysis[:data_loss] << "Contract linkage"
    end
  end

  # === EXECUTION METHODS ===

  def break_ticketing_connections
    count = production.ticketing_production_links.count
    production.ticketing_production_links.destroy_all
    @changes_made << "Removed #{count} ticketing links" if count > 0
  end

  def break_contract_connections
    if production.contract_id.present?
      production.update!(contract_id: nil)
      @changes_made << "Unlinked from contract"
    end
  end

  def break_casting_table_connections
    count = CastingTableProduction.where(production: production).delete_all
    @changes_made << "Removed from #{count} casting tables" if count > 0
  end

  def break_payroll_connections
    if production.payroll_schedule.present?
      production.payroll_schedule.destroy
      @changes_made << "Deleted payroll schedule"
    end
  end

  def clear_production_permissions
    count = production.production_permissions.count
    production.production_permissions.delete_all
    @changes_made << "Removed #{count} production permissions" if count > 0
  end

  def clear_team_invitations
    count = production.team_invitations.count
    production.team_invitations.destroy_all
    @changes_made << "Deleted #{count} team invitations" if count > 0
  end

  def migrate_talent_pool_members_to_target_org
    talent_pool = production.talent_pool
    return unless talent_pool

    people_added = 0
    groups_added = 0

    talent_pool.people.find_each do |person|
      unless target_org.people.include?(person)
        target_org.people << person
        people_added += 1
      end
    end

    talent_pool.groups.find_each do |group|
      unless target_org.groups.include?(group)
        target_org.groups << group
        groups_added += 1
      end
    end

    @changes_made << "Added #{people_added} people to target org directory" if people_added > 0
    @changes_made << "Added #{groups_added} groups to target org directory" if groups_added > 0
  end

  def break_talent_pool_shares
    # Outgoing shares (production using another pool)
    outgoing = production.talent_pool_shares.count
    production.talent_pool_shares.destroy_all

    # Incoming shares (others using this production's pool)
    incoming = production.talent_pool&.talent_pool_shares&.count || 0
    production.talent_pool&.talent_pool_shares&.destroy_all

    total = outgoing + incoming
    @changes_made << "Broke #{total} talent pool shares" if total > 0
  end

  def apply_location_mappings
    return unless @analysis[:location_analysis]

    # Build complete mapping: source_id => target_id
    # Start with auto-matched locations
    complete_mappings = {}

    @analysis[:location_analysis][:auto_matched].each do |match|
      complete_mappings[match[:source_id]] = match[:target_id]
    end

    # Process user-provided mappings
    # Special value "copy" means copy the location to target org
    copied_locations = {} # source_id => new_target_id

    location_mappings.each do |source_id, value|
      source_id = source_id.to_i
      value = value.to_s

      if value == "copy"
        # Copy the location (and its spaces) to target org
        new_location = copy_location_to_target_org(source_id)
        if new_location
          copied_locations[source_id] = new_location.id
          complete_mappings[source_id] = new_location.id
        end
      elsif value.to_i > 0
        complete_mappings[source_id] = value.to_i
      end
      # If value is empty or 0, don't add to mappings (will be cleared)
    end

    # Apply mappings to shows
    mapped_count = 0
    cleared_count = 0

    production.shows.where.not(location_id: nil).find_each do |show|
      target_location_id = complete_mappings[show.location_id]

      if target_location_id
        show.update_columns(location_id: target_location_id, location_space_id: nil)
        mapped_count += 1
      else
        show.update_columns(location_id: nil, location_space_id: nil)
        cleared_count += 1
      end
    end

    @changes_made << "Copied #{copied_locations.count} locations to target org" if copied_locations.any?
    @changes_made << "Mapped locations for #{mapped_count} shows" if mapped_count > 0
    @changes_made << "Cleared location references from #{cleared_count} shows" if cleared_count > 0
  end

  def copy_location_to_target_org(source_location_id)
    source_location = Location.find_by(id: source_location_id)
    return nil unless source_location

    # Create new location in target org with same attributes
    new_location = target_org.locations.create!(
      name: source_location.name,
      address1: source_location.address1,
      address2: source_location.address2,
      city: source_location.city,
      state: source_location.state,
      postal_code: source_location.postal_code,
      default: false # Don't make copied locations default
    )

    # Copy all spaces
    source_location.location_spaces.find_each do |space|
      new_location.location_spaces.create!(
        name: space.name,
        description: space.description,
        default: space.default
      )
    end

    new_location
  end

  def update_message_organization_references
    count = Message.where(production: production).update_all(organization_id: target_org.id)
    @changes_made << "Updated organization on #{count} messages" if count > 0
  end

  def update_log_organization_references
    email_count = EmailLog.where(production_id: production.id).update_all(organization_id: target_org.id)
    sms_count = SmsLog.where(production_id: production.id).update_all(organization_id: target_org.id)

    @changes_made << "Updated #{email_count} email logs" if email_count > 0
    @changes_made << "Updated #{sms_count} SMS logs" if sms_count > 0
  end

  def update_payroll_run_references
    count = production.payroll_runs.update_all(organization_id: target_org.id)
    @changes_made << "Updated #{count} payroll runs" if count > 0
  end
end
