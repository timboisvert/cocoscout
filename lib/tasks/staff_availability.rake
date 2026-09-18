# frozen_string_literal: true

# Staff work availability is moving from region marks (staff_unavailabilities)
# to time bands (staff_availability_entries). Until the new staff screen takes
# over, every write to the old table is mirrored into the new one; these tasks
# fill in what existed before the mirror, and show where the two disagree.
namespace :staff_availability do
  desc "Mirror every person's existing availability marks into time-band entries (idempotent)"
  task backfill: :environment do
    count = StaffAvailabilityBackfill.rebuild_all!
    puts "Rebuilt availability entries for #{count} #{'person'.pluralize(count)}."
  end

  # Ask old and new about every upcoming shift and every active staff member of
  # the shift's org. Disagreements are expected, and they're the reason for the
  # change — the new model reads a shift's whole span where the old one read only
  # its start, and a region the org hasn't switched on no longer means "nothing".
  # This lists them so they're seen before anything relies on the new answer.
  desc "Compare old and new availability answers for upcoming shifts (read-only). DAYS=28"
  task parity: :environment do
    days = ENV.fetch("DAYS", "28").to_i
    from = Date.current
    to = from + days

    shifts = Shift.where(starts_at: from.beginning_of_day..to.end_of_day).includes(:organization).to_a
    staff_by_org = OrganizationStaffMember.active.where(organization_id: shifts.map(&:organization_id).uniq)
                                          .pluck(:organization_id, :person_id)
                                          .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    person_ids = staff_by_org.values.flatten.uniq
    modes = Person.where(id: person_ids).pluck(:id, :availability_mode).to_h
    marks = StaffUnavailability.where(person_id: person_ids, date: (from - 1)..(to + 1)).group_by(&:person_id)
    resolver = StaffAvailabilityResolver.new(person_ids, from: from, to: to)

    tally = Hash.new(0)
    samples = Hash.new { |h, k| h[k] = [] }

    shifts.each do |shift|
      staff_by_org.fetch(shift.organization_id, []).each do |pid|
        old = StaffUnavailability.unavailable_for?(mode: modes[pid] || "unavailable", entries: marks.fetch(pid, []),
                                                   time: shift.starts_at, organization: shift.organization)
        verdict = resolver.verdict(pid, shift.starts_at, shift.ends_at)
        new = verdict.flagged?

        key =
          if old == new then :agree
          elsif new then :new_only
          else :old_only
          end
        tally[key] += 1
        next if key == :agree || samples[key].size >= 10

        samples[key] << "  shift ##{shift.id} #{shift.starts_at.strftime('%a %b %-d %-l:%M%p')}–" \
                        "#{shift.ends_at.strftime('%-l:%M%p')}  person ##{pid}  new=#{verdict.status}"
      end
    end

    total = tally.values.sum
    puts "Checked #{total} (shift, staff member) pairs over the next #{days} days."
    puts "  agree:    #{tally[:agree]}"
    puts "  new only: #{tally[:new_only]}  (flagged now, not before — usually a shift that starts " \
         "outside a blocked stretch but runs into it)"
    puts "  old only: #{tally[:old_only]}  (flagged before, not now — look at these closely)"
    %i[new_only old_only].each do |key|
      next if samples[key].empty?

      puts "\n#{key.to_s.tr('_', ' ')} examples:"
      puts samples[key]
    end
  end
end
