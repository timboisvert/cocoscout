# frozen_string_literal: true

# What a show needs (after-V1 #6): its production's services
# (ProductionServiceNeed), its contract's (a per-event line on the show's
# date, a once line on every show the contract books), and where the show
# differs (ShowServiceChange: drop one, add one, change how many people).
#
#   needs = ShowServices.new(shows)        # batch: one set of queries for a week
#   needs.for(show)                        # => [Need, ...] (dropped ones included)
#   needs.for(show).select(&:needed?)
#
#   ShowServices.save!(show, rows)         # the show Settings tab's checkboxes
#   ShowServices.change!(show, service, needed: false)
class ShowServices
  # source: :production, :contract or :show (added for this show alone).
  Need = Struct.new(:service, :people_count, :source, :dropped, keyword_init: true) do
    def needed?
      !dropped
    end

    def staffed?
      service.staffed?
    end
  end

  LIVE_CONTRACT_STATUSES = %w[active completed].freeze

  def initialize(shows)
    @shows = Array(shows)
    production_ids = @shows.map(&:production_id).uniq
    @production_needs = ProductionServiceNeed.where(production_id: production_ids)
                                             .includes(house_service: :house_roles).group_by(&:production_id)
    @changes = ShowServiceChange.where(show_id: @shows.map(&:id))
                                .includes(house_service: :house_roles).group_by(&:show_id)
    @contracts_by_production = Contract.where(production_id: production_ids, status: LIVE_CONTRACT_STATUSES).group_by(&:production_id)
    rental_ids = @shows.map(&:space_rental_id).compact.uniq
    @rental_contracts = SpaceRental.where(id: rental_ids).includes(:contract).to_h { |r| [ r.id, r.contract ] }
    org_ids = Production.where(id: production_ids).distinct.pluck(:organization_id)
    @services = HouseService.where(organization_id: org_ids).includes(:house_roles).to_a
  end

  # Everything the show would need, then its own changes applied: a dropped
  # service stays in the list (marked dropped) so it can be put back.
  def for(show)
    needs = base(show)
    Array(@changes[show.id]).each do |change|
      if (need = needs[change.house_service_id])
        change.needed? ? need.people_count = change.people_count : need.dropped = true
      elsif change.needed?
        needs[change.house_service_id] = Need.new(service: change.house_service, people_count: change.people_count, source: :show, dropped: false)
      end
    end
    needs.values.sort_by { |n| [ n.service.position, n.service.name.downcase ] }
  end

  # What the show gets before its own changes: { service_id => Need }.
  def base(show)
    needs = {}
    Array(@production_needs[show.production_id]).each do |pn|
      needs[pn.house_service_id] = Need.new(service: pn.house_service, people_count: pn.people_count, source: :production, dropped: false)
    end
    contract_services(show).each do |service|
      need = needs[service.id] ||= Need.new(service: service, people_count: 1, dropped: false)
      need.source = :contract
    end
    needs
  end

  # The contract booking this show (its space rental's, else its production's
  # only signed one), when it's live.
  def contract_for(show)
    rental = @rental_contracts[show.space_rental_id]
    return rental if rental && rental.status.in?(LIVE_CONTRACT_STATUSES)

    live = Array(@contracts_by_production[show.production_id])
    live.one? ? live.first : nil
  end

  # Each service a show changes from its production or contract, for one
  # show's save: rows are { service_id => { "needed" => "1"/"0", "people" => "2" } }
  # for every service listed. Anything matching what it'd get anyway leaves no
  # change behind.
  def self.save!(show, rows, services:)
    resolver = new([ show ])
    base = resolver.base(show)
    rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
    ShowServiceChange.transaction do
      services.each do |service|
        row = rows[service.id.to_s] || rows[service.id]
        next unless row

        wanted = row["needed"] == "1"
        people = row["people"].to_i.clamp(1, 20)
        write_change(show, service, base[service.id], wanted, people)
      end
    end
  end

  # One service, one show, from the show's panel on Scheduling: needed false
  # is "Not this show", true adds it (or puts back one dropped).
  def self.change!(show, service, needed:, people: nil)
    base = new([ show ]).base(show)[service.id]
    people ||= base&.people_count || 1
    write_change(show, service, base, needed, people)
  end

  def self.write_change(show, service, base, wanted, people)
    # Not through show.show_service_changes: a change built there and then
    # not needed would linger in the association and save with the show.
    change = ShowServiceChange.find_or_initialize_by(show: show, house_service: service)
    same_as_base = base ? (wanted && people == base.people_count) : !wanted
    if same_as_base
      change.destroy! if change.persisted?
    else
      change.update!(needed: wanted, people_count: people)
    end
  end
  private_class_method :write_change

  private

  def contract_services(show)
    contract = contract_for(show)
    return [] unless contract

    by_id = @services.index_by(&:id)
    by_name = @services.select { |s| s.organization_id == contract.organization_id }.index_by { |s| s.name.downcase }
    show_date = show.date_and_time.to_date
    contract.draft_services.filter_map do |line|
      service = by_id[line["service_id"].to_i] || by_name[line["name"].to_s.downcase]
      next unless service && service.organization_id == contract.organization_id

      if line["per_event"]
        dates = Array(line["events"]).filter_map { |e| Time.zone.parse(e["starts_at"].to_s)&.to_date rescue nil }
        next unless dates.include?(show_date)
      end
      service
    end.uniq
  end
end
