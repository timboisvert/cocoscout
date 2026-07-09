# frozen_string_literal: true

# Consolidates duplicate productions (created by the contract/course bugs) down to
# a single "winner" per group, moving ALL data onto the winner so nothing is lost:
#
#   * winner is chosen automatically by how much real work lives on it
#     (cast assignments, then shows, then offerings, then having a contract, then age)
#   * each loser's shows are moved to the winner; shows that share the exact
#     start time are merged (their casting is folded in) so you don't get doubles
#   * course offerings, messages, and the contract link are moved to the winner
#   * the emptied loser productions are deleted
#
# Use DuplicateProductionMerger.duplicate_groups to find groups, then #call each.
# Pass dry_run: true (default) to preview the actions without touching data.
class DuplicateProductionMerger
  Result = Struct.new(:winner, :losers, :actions, keyword_init: true)

  # Find sets of productions that are duplicates of each other:
  #   A) more than one production sharing a contract (the course-husk bug), and
  #   B) same-name productions in an org where at least one is contract-linked
  #      (the "made it manually, then made a contract" bug) — the contract
  #      requirement avoids merging legitimately-separate same-name productions.
  def self.duplicate_groups(organization = nil)
    org_scope = organization ? Production.where(organization_id: organization.id) : Production.all

    groups = []

    Production.where.not(contract_id: nil)
              .group(:contract_id).having("COUNT(*) > 1")
              .pluck(:contract_id)
              .each { |cid| groups << Production.where(contract_id: cid).to_a }

    org_scope.group(:organization_id, :name).having("COUNT(*) > 1").count.each_key do |(org_id, name)|
      prods = Production.where(organization_id: org_id, name: name).to_a
      groups << prods if prods.any? { |p| p.contract_id.present? }
    end

    coalesce(groups)
  end

  # Merge groups that share any production into single groups via union-find, so a
  # production caught by several rules ends up in exactly ONE group (otherwise one
  # group could delete a production a later group still references).
  def self.coalesce(groups)
    parent = {}
    find = lambda do |x|
      parent[x] = x unless parent.key?(x)
      parent[x] = find.call(parent[x]) unless parent[x] == x
      parent[x]
    end
    union = ->(a, b) { parent[find.call(a)] = find.call(b) }

    prod_by_id = {}
    groups.each do |group|
      group.each { |p| prod_by_id[p.id] = p; find.call(p.id) }
      group.map(&:id).each_cons(2) { |a, b| union.call(a, b) }
    end

    buckets = Hash.new { |h, k| h[k] = [] }
    prod_by_id.each_key { |id| buckets[find.call(id)] << prod_by_id[id] }
    buckets.values.select { |bucket| bucket.size > 1 }
  end

  def initialize(productions)
    @productions = productions.uniq(&:id)
  end

  def call(dry_run: true)
    # Re-fetch live rows so a production already removed by an earlier group (or a
    # previous run) can't crash us — it simply drops out of the group.
    productions = Production.where(id: @productions.map(&:id)).to_a
    return Result.new(winner: productions.first, losers: [], actions: [ "fewer than 2 live productions — nothing to do" ]) if productions.size < 2

    winner = productions.max_by { |p| score(p) }
    losers = productions - [ winner ]
    actions = [ "WINNER ##{winner.id} #{winner.name.inspect} (type=#{winner.production_type}, score=#{score(winner).inspect})" ]

    ActiveRecord::Base.transaction do
      losers.each { |loser| merge_loser(loser, winner, actions, dry_run) }

      # A production that carries a contract is a third-party production. If the
      # winner was a manually-created in_house one, fix its type so revenue-share
      # sync/settlement (gated on type_third_party?) still runs for the contract.
      will_carry_contract = winner.contracts.any? || losers.any? { |l| l.contracts.any? }
      if will_carry_contract && winner.production_type == "in_house"
        actions << "  set winner ##{winner.id} to third_party (now carries a contract)"
        winner.update!(production_type: "third_party") unless dry_run
      end

      raise ActiveRecord::Rollback if dry_run
    end

    Result.new(winner: winner, losers: losers, actions: actions)
  end

  private

  # Higher is more canonical. Arrays compare left-to-right; -id makes the older
  # (lower id) production win ties.
  def score(production)
    [
      production.show_person_role_assignments.count,
      production.shows.count,
      production.course_offerings.count,
      production.contracts.count,
      -production.id
    ]
  end

  def merge_loser(loser, winner, actions, dry_run)
    loser.shows.reload.to_a.each do |show|
      twin = winner.shows.find_by(date_and_time: show.date_and_time)
      if twin
        actions << "  merge duplicate show ##{show.id} into ##{twin.id} (#{show.date_and_time})"
        merge_show(show, twin) unless dry_run
      else
        actions << "  move show ##{show.id} (#{show.date_and_time}) to winner"
        show.update!(production_id: winner.id) unless dry_run
      end
    end

    loser.course_offerings.reload.each do |offering|
      actions << "  move course offering ##{offering.id} to winner"
      offering.update!(production_id: winner.id) unless dry_run
    end

    loser.messages.reload.each do |message|
      message.update!(production_id: winner.id) unless dry_run
    end

    # Re-point every contract on the loser to the winner. A production can carry
    # many contracts, so two valid contracts for the same show end up on one production.
    loser.contracts.reload.each do |contract|
      actions << "  move contract ##{contract.id} onto winner ##{winner.id}"
      contract.update!(production: winner) unless dry_run
    end

    actions << "  delete emptied production ##{loser.id}"
    # Re-fetch a clean row so its cached `shows`/`course_offerings` (which we just
    # moved to the winner) aren't re-destroyed by dependent: :destroy. Guarded so an
    # already-removed row can't crash the run.
    Production.where(id: loser.id).first&.destroy! unless dry_run
  end

  # Fold a duplicate show's casting into the surviving twin, then delete it.
  def merge_show(loser_show, twin)
    loser_show.show_person_role_assignments.reload.each do |assignment|
      exists = twin.show_person_role_assignments.exists?(
        role_id: assignment.role_id,
        assignable_type: assignment.assignable_type,
        assignable_id: assignment.assignable_id
      )
      exists ? assignment.destroy! : assignment.update!(show_id: twin.id)
    end
    ShowCastNotification.where(show_id: loser_show.id).update_all(show_id: twin.id)
    loser_show.reload.destroy!
  end
end
