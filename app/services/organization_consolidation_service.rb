# frozen_string_literal: true

# Service to consolidate (merge) one Organization into another.
# Moves ALL productions and org-level resources, keeping connections intact.
#
# The key advantage over per-production transfer: since everything moves together,
# cross-production connections (casting tables, talent pool shares, contracts) stay intact.
#
# Usage:
#   result = OrganizationConsolidationService.analyze(source_org, target_org)
#   result = OrganizationConsolidationService.execute(source_org, target_org, location_mappings: {})
#
class OrganizationConsolidationService
  class ConsolidationError < StandardError; end

  attr_reader :source_org, :target_org, :analysis, :changes_made, :location_mappings

  def initialize(source_org, target_org, location_mappings: {})
    @source_org = source_org
    @target_org = target_org
    @location_mappings = location_mappings
    @analysis = {}
    @changes_made = []
  end

  def self.analyze(source_org, target_org)
    new(source_org, target_org).analyze
  end

  def self.execute(source_org, target_org, location_mappings: {})
    new(source_org, target_org, location_mappings: location_mappings).execute
  end

  def analyze
    @analysis = {
      source_org: { id: source_org.id, name: source_org.name },
      target_org: { id: target_org.id, name: target_org.name },
      warnings: [],
      data_loss: [],
      migrations: [],
      location_analysis: nil
    }

    validate!

    analyze_productions
    analyze_locations
    analyze_payout_schemes
    analyze_casting_tables
    analyze_contracts_and_contractors
    analyze_agreement_templates
    analyze_ticketing_providers
    analyze_seating_configurations
    analyze_directory
    analyze_team_members
    analyze_messages_and_logs
    analyze_payroll

    @analysis
  end

  def execute
    analyze

    ActiveRecord::Base.transaction do
      # 1. Location mapping (must happen before productions move, since shows reference locations)
      apply_location_mappings

      # 2. Move org-level payout schemes (before productions, so show_payouts keep references)
      migrate_payout_schemes

      # 3. Move contracts and contractors
      migrate_contractors
      migrate_contracts

      # 4. Move casting tables (before productions, so casting_table_productions stay valid)
      migrate_casting_tables

      # 5. Move agreement templates
      migrate_agreement_templates

      # 6. Move ticketing providers (and their sync rules)
      migrate_ticketing_providers

      # 7. Move seating configurations (update location references after mapping)
      migrate_seating_configurations

      # 8. Move directory (people and groups)
      migrate_directory

      # 9. Move team members
      migrate_team_members

      # 10. Move payroll schedule
      migrate_payroll_schedule

      # 11. Move all productions (the big one — this also moves talent pools, shows, etc.)
      migrate_productions

      # 12. Update organization references on messages, email logs, payroll runs
      update_message_references
      update_email_log_references
      update_payroll_run_references

      # 13. Move team invitations
      migrate_team_invitations

      @changes_made << "Organization consolidation complete: #{source_org.name} → #{target_org.name}"
    end

    { success: true, changes: @changes_made }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  private

  def validate!
    raise ConsolidationError, "Source and target organization are the same" if source_org.id == target_org.id
    raise ConsolidationError, "Source organization not found" unless source_org.present?
    raise ConsolidationError, "Target organization not found" unless target_org.present?
  end

  # === ANALYSIS METHODS ===

  def analyze_productions
    count = source_org.productions.count
    if count > 0
      @analysis[:migrations] << {
        category: "Productions",
        count: count,
        action: "Will be moved to target organization",
        details: source_org.productions.pluck(:name)
      }
    end

    # Talent pool shares — since all productions move together, these stay valid
    share_count = TalentPoolShare.joins(talent_pool: :production)
                                 .where(productions: { organization_id: source_org.id })
                                 .count
    if share_count > 0
      @analysis[:migrations] << {
        category: "Talent Pool Shares",
        count: share_count,
        action: "Will remain intact (all productions move together)"
      }
    end
  end

  def analyze_locations
    source_locations = source_org.locations.to_a
    return if source_locations.empty?

    target_locations = target_org.locations.order(:name).to_a
    target_by_name = target_locations.index_by { |l| l.name.downcase.strip }

    auto_matched = []
    needs_mapping = []

    source_locations.each do |loc|
      show_count = loc.shows.count
      target_match = target_by_name[loc.name.downcase.strip]

      if target_match
        auto_matched << {
          source_id: loc.id,
          source_name: loc.name,
          target_id: target_match.id,
          target_name: target_match.name,
          show_count: show_count
        }
      else
        needs_mapping << {
          source_id: loc.id,
          source_name: loc.name,
          source_address: loc.respond_to?(:full_address) ? loc.full_address : nil,
          space_count: loc.location_spaces.count,
          show_count: show_count
        }
      end
    end

    @analysis[:location_analysis] = {
      total_source_locations: source_locations.count,
      auto_matched: auto_matched,
      needs_mapping: needs_mapping,
      target_locations: target_locations.map { |l| { id: l.id, name: l.name } }
    }

    if auto_matched.any?
      @analysis[:migrations] << {
        category: "Locations (Auto-Matched)",
        count: auto_matched.count,
        action: "Will map to matching locations in target org by name"
      }
    end

    if needs_mapping.any?
      @analysis[:warnings] << {
        category: "Locations",
        message: "#{needs_mapping.count} location(s) need mapping",
        details: needs_mapping.map { |l| "#{l[:source_name]} (#{l[:show_count]} shows)" }
      }
    end
  end

  def analyze_payout_schemes
    org_level = source_org.payout_schemes.organization_level
    count = org_level.count
    return unless count > 0

    # Check for name conflicts
    target_names = target_org.payout_schemes.organization_level.pluck(:name).map(&:downcase)
    conflicts = org_level.select { |ps| target_names.include?(ps.name.downcase) }

    @analysis[:migrations] << {
      category: "Org-Level Payout Schemes",
      count: count,
      action: "Will be moved to target organization"
    }

    if conflicts.any?
      @analysis[:warnings] << {
        category: "Payout Scheme Name Conflicts",
        message: "#{conflicts.count} scheme(s) have duplicate names — will be renamed",
        details: conflicts.map(&:name)
      }
    end
  end

  def analyze_casting_tables
    count = source_org.casting_tables.count
    return unless count > 0

    @analysis[:migrations] << {
      category: "Casting Tables",
      count: count,
      action: "Will be moved to target organization (production links preserved)"
    }
  end

  def analyze_contracts_and_contractors
    contractor_count = source_org.contractors.count
    contract_count = source_org.contracts.count

    if contractor_count > 0
      target_names = target_org.contractors.pluck(:name).map(&:downcase)
      conflicts = source_org.contractors.select { |c| target_names.include?(c.name.downcase) }

      @analysis[:migrations] << {
        category: "Contractors",
        count: contractor_count,
        action: "Will be moved to target organization"
      }

      if conflicts.any?
        @analysis[:warnings] << {
          category: "Contractor Name Conflicts",
          message: "#{conflicts.count} contractor(s) have duplicate names — will be merged",
          details: conflicts.map(&:name)
        }
      end
    end

    if contract_count > 0
      @analysis[:migrations] << {
        category: "Contracts",
        count: contract_count,
        action: "Will be moved to target organization (contractor links preserved)"
      }
    end
  end

  def analyze_agreement_templates
    count = source_org.agreement_templates.count
    return unless count > 0

    @analysis[:migrations] << {
      category: "Agreement Templates",
      count: count,
      action: "Will be moved to target organization"
    }
  end

  def analyze_ticketing_providers
    count = source_org.ticketing_providers.count
    return unless count > 0

    @analysis[:migrations] << {
      category: "Ticketing Providers",
      count: count,
      action: "Will be moved to target organization"
    }

    sync_rule_count = source_org.ticket_sync_rules.count
    if sync_rule_count > 0
      @analysis[:migrations] << {
        category: "Ticket Sync Rules",
        count: sync_rule_count,
        action: "Will be moved with their ticketing providers"
      }
    end
  end

  def analyze_seating_configurations
    count = source_org.seating_configurations.count
    return unless count > 0

    @analysis[:migrations] << {
      category: "Seating Configurations",
      count: count,
      action: "Will be moved to target organization (location references updated)"
    }
  end

  def analyze_directory
    people_count = source_org.people.count
    groups_count = source_org.groups.count

    people_already_in_target = source_org.people.where(id: target_org.people.select(:id)).count
    groups_already_in_target = source_org.groups.where(id: target_org.groups.select(:id)).count

    new_people = people_count - people_already_in_target
    new_groups = groups_count - groups_already_in_target

    if new_people > 0
      @analysis[:migrations] << {
        category: "People (Directory)",
        count: new_people,
        action: "Will be added to target organization's directory"
      }
    end

    if people_already_in_target > 0
      @analysis[:migrations] << {
        category: "People (Already in Target)",
        count: people_already_in_target,
        action: "Already exist in target — will be skipped"
      }
    end

    if new_groups > 0
      @analysis[:migrations] << {
        category: "Groups (Directory)",
        count: new_groups,
        action: "Will be added to target organization's directory"
      }
    end
  end

  def analyze_team_members
    # Organization roles (team members)
    source_user_ids = source_org.organization_roles.pluck(:user_id)
    target_user_ids = target_org.organization_roles.pluck(:user_id)

    new_members = source_user_ids - target_user_ids - [target_org.owner_id]
    already_members = source_user_ids & target_user_ids

    if new_members.any?
      @analysis[:migrations] << {
        category: "Team Members",
        count: new_members.count,
        action: "Will be added to target organization as members"
      }
    end

    if already_members.any?
      @analysis[:migrations] << {
        category: "Team Members (Already in Target)",
        count: already_members.count,
        action: "Already in target — will be skipped"
      }
    end

    # Production permissions stay with productions
    perm_count = ProductionPermission.joins(:production)
                                     .where(productions: { organization_id: source_org.id })
                                     .count
    if perm_count > 0
      @analysis[:migrations] << {
        category: "Production Permissions",
        count: perm_count,
        action: "Will remain intact (move with their productions)"
      }
    end
  end

  def analyze_messages_and_logs
    message_count = Message.where(organization_id: source_org.id).count
    if message_count > 0
      @analysis[:migrations] << {
        category: "Messages",
        count: message_count,
        action: "Organization reference will be updated to target"
      }
    end

    email_log_count = EmailLog.where(organization_id: source_org.id).count
    if email_log_count > 0
      @analysis[:migrations] << {
        category: "Email Logs",
        count: email_log_count,
        action: "Organization reference will be updated to target"
      }
    end
  end

  def analyze_payroll
    if source_org.payroll_schedule.present?
      if target_org.payroll_schedule.present?
        @analysis[:warnings] << {
          category: "Payroll Schedule",
          message: "Both orgs have a payroll schedule — source schedule will be deleted",
          details: []
        }
        @analysis[:data_loss] << "Source org payroll schedule (target org already has one)"
      else
        @analysis[:migrations] << {
          category: "Payroll Schedule",
          count: 1,
          action: "Will be moved to target organization"
        }
      end
    end

    payroll_run_count = source_org.payroll_runs.count
    if payroll_run_count > 0
      @analysis[:migrations] << {
        category: "Payroll Runs",
        count: payroll_run_count,
        action: "Organization reference will be updated to target"
      }
    end
  end

  # === EXECUTION METHODS ===

  def apply_location_mappings
    return unless @analysis[:location_analysis]

    complete_mappings = {}

    # Auto-matched locations
    @analysis[:location_analysis][:auto_matched].each do |match|
      complete_mappings[match[:source_id]] = match[:target_id]
    end

    # User-provided mappings
    location_mappings.each do |source_id, value|
      source_id = source_id.to_i
      value = value.to_s

      if value == "copy"
        new_location = copy_location_to_target_org(source_id)
        complete_mappings[source_id] = new_location.id if new_location
      elsif value.to_i > 0
        complete_mappings[source_id] = value.to_i
      end
    end

    # Update show location references across ALL source org productions
    mapped_count = 0
    cleared_count = 0

    Show.joins(:production)
        .where(productions: { organization_id: source_org.id })
        .where.not(location_id: nil)
        .find_each do |show|
      target_location_id = complete_mappings[show.location_id]
      if target_location_id
        show.update_columns(location_id: target_location_id, location_space_id: nil)
        mapped_count += 1
      else
        show.update_columns(location_id: nil, location_space_id: nil)
        cleared_count += 1
      end
    end

    # Update audition session location references
    AuditionSession.joins(audition_cycle: :production)
                   .where(productions: { organization_id: source_org.id })
                   .where.not(location_id: nil)
                   .find_each do |session|
      target_location_id = complete_mappings[session.location_id]
      if target_location_id
        session.update_columns(location_id: target_location_id)
      else
        session.update_columns(location_id: nil)
      end
    end if defined?(AuditionSession)

    @changes_made << "Mapped locations for #{mapped_count} shows" if mapped_count > 0
    @changes_made << "Cleared location from #{cleared_count} shows" if cleared_count > 0
  end

  def copy_location_to_target_org(source_location_id)
    source = Location.find_by(id: source_location_id)
    return nil unless source

    new_location = target_org.locations.create!(
      name: source.name,
      address1: source.address1,
      address2: source.address2,
      city: source.city,
      state: source.state,
      postal_code: source.postal_code,
      default: false
    )

    source.location_spaces.find_each do |space|
      new_location.location_spaces.create!(
        name: space.name,
        description: space.description,
        default: space.default
      )
    end

    @changes_made << "Copied location '#{source.name}' to target org"
    new_location
  end

  def migrate_payout_schemes
    target_names = target_org.payout_schemes.organization_level.pluck(:name).map(&:downcase)
    moved_count = 0

    source_org.payout_schemes.organization_level.find_each do |scheme|
      # Handle name conflicts by appending source org name
      if target_names.include?(scheme.name.downcase)
        scheme.update_columns(name: "#{scheme.name} (from #{source_org.name})")
      end
      scheme.update_columns(organization_id: target_org.id)
      moved_count += 1
    end

    @changes_made << "Moved #{moved_count} org-level payout schemes" if moved_count > 0
  end

  def migrate_contractors
    target_contractors_by_name = target_org.contractors.index_by { |c| c.name.downcase.strip }
    merged_count = 0
    moved_count = 0

    source_org.contractors.find_each do |contractor|
      existing = target_contractors_by_name[contractor.name.downcase.strip]
      if existing
        # Merge: reassign contracts from source contractor to existing target contractor
        contractor.contracts.update_all(contractor_id: existing.id)
        contractor.destroy
        merged_count += 1
      else
        contractor.update_columns(organization_id: target_org.id)
        moved_count += 1
      end
    end

    @changes_made << "Moved #{moved_count} contractors" if moved_count > 0
    @changes_made << "Merged #{merged_count} duplicate contractors" if merged_count > 0
  end

  def migrate_contracts
    count = source_org.contracts.update_all(organization_id: target_org.id)
    @changes_made << "Moved #{count} contracts" if count > 0
  end

  def migrate_casting_tables
    count = source_org.casting_tables.update_all(organization_id: target_org.id)
    @changes_made << "Moved #{count} casting tables" if count > 0
  end

  def migrate_agreement_templates
    count = source_org.agreement_templates.update_all(organization_id: target_org.id)
    @changes_made << "Moved #{count} agreement templates" if count > 0
  end

  def migrate_ticketing_providers
    # Sync rules reference both org and provider — move providers first, then rules follow
    count = source_org.ticketing_providers.update_all(organization_id: target_org.id)
    @changes_made << "Moved #{count} ticketing providers" if count > 0

    rule_count = source_org.ticket_sync_rules.update_all(organization_id: target_org.id)
    @changes_made << "Moved #{rule_count} ticket sync rules" if rule_count > 0
  end

  def migrate_seating_configurations
    # Seating configs may reference locations — update those references using the location mapping
    if @analysis[:location_analysis]
      complete_mappings = {}
      @analysis[:location_analysis][:auto_matched].each { |m| complete_mappings[m[:source_id]] = m[:target_id] }
      location_mappings.each do |source_id, value|
        next if value.to_s.empty?
        complete_mappings[source_id.to_i] = value.to_i if value.to_s != "copy"
      end

      source_org.seating_configurations.where.not(location_id: nil).find_each do |config|
        new_loc = complete_mappings[config.location_id]
        config.update_columns(location_id: new_loc) if new_loc
      end
    end

    count = source_org.seating_configurations.update_all(organization_id: target_org.id)
    @changes_made << "Moved #{count} seating configurations" if count > 0
  end

  def migrate_directory
    # People
    existing_person_ids = target_org.people.pluck(:id)
    new_people = source_org.people.where.not(id: existing_person_ids)
    new_people.find_each { |person| target_org.people << person }
    people_added = new_people.count
    @changes_made << "Added #{people_added} people to target directory" if people_added > 0

    # Groups
    existing_group_ids = target_org.groups.pluck(:id)
    new_groups = source_org.groups.where.not(id: existing_group_ids)
    new_groups.find_each { |group| target_org.groups << group }
    groups_added = new_groups.count
    @changes_made << "Added #{groups_added} groups to target directory" if groups_added > 0
  end

  def migrate_team_members
    target_user_ids = target_org.organization_roles.pluck(:user_id) + [target_org.owner_id]

    source_org.organization_roles.find_each do |role|
      if target_user_ids.include?(role.user_id)
        # Already a member in target — skip
        role.destroy
      else
        role.update_columns(organization_id: target_org.id)
      end
    end

    @changes_made << "Migrated team members"
  end

  def migrate_payroll_schedule
    source_schedule = source_org.payroll_schedule
    return unless source_schedule

    if target_org.payroll_schedule.present?
      source_schedule.destroy
      @changes_made << "Deleted source payroll schedule (target already has one)"
    else
      source_schedule.update_columns(organization_id: target_org.id)
      @changes_made << "Moved payroll schedule to target"
    end
  end

  def migrate_productions
    # Production-level payout schemes also have organization_id — update them
    prod_scheme_count = PayoutScheme.where(organization_id: source_org.id).production_level
                                    .update_all(organization_id: target_org.id)
    @changes_made << "Updated #{prod_scheme_count} production-level payout schemes" if prod_scheme_count > 0

    count = source_org.productions.update_all(organization_id: target_org.id)
    @changes_made << "Moved #{count} productions" if count > 0

    # TalentPoolShare same_organization validation won't run on update_all,
    # but since all productions move together, the constraint stays satisfied.
  end

  def update_message_references
    count = Message.where(organization_id: source_org.id).update_all(organization_id: target_org.id)
    @changes_made << "Updated #{count} message references" if count > 0
  end

  def update_email_log_references
    count = EmailLog.where(organization_id: source_org.id).update_all(organization_id: target_org.id)
    @changes_made << "Updated #{count} email log references" if count > 0
  end

  def update_payroll_run_references
    count = PayrollRun.where(organization_id: source_org.id).update_all(organization_id: target_org.id)
    @changes_made << "Updated #{count} payroll run references" if count > 0
  end

  def migrate_team_invitations
    count = source_org.team_invitations.update_all(organization_id: target_org.id)
    @changes_made << "Moved #{count} team invitations" if count > 0
  end
end
