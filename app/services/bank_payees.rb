# frozen_string_literal: true

# Who a bank line is from or to, read from the bank's own formats (Books
# V1.3; Tim, 2026-11-03, after a year's statement came in as 243 payee
# groups with Facebook three times and his own name four). Each line gets
# a reading: its kind (a bank draft, a Zelle to a person, a card purchase,
# a transfer between the organization's own accounts, a check, a deposit
# the organization made, a cash withdrawal, a bank fee), the name of the
# payee when the line names one, and the phrase a rule would use to catch
# it. Lines with the same name and direction make a Group: what the
# sorting mode (BankSort) takes one at a time and the Rules page lists.
#
#   BankPayees.read("Zelle payment to Jaki Torres Cleaner JPM99cpv028k")
#     # => Reading(kind: "zelle_to", name: "Jaki Torres Cleaner", phrase: "to Jaki Torres Cleaner")
#   BankPayees.groups(organization)   # waiting lines, grouped, most lines first
class BankPayees
  KINDS = {
    "draft" => "Bank draft", "provider" => "Payouts from a payment provider", "zelle_to" => "Zelle to a person", "zelle_from" => "Zelle from a person",
    "online" => "Online payment", "transfer" => "Transfers between your own accounts", "check" => "Checks", "deposit" => "Deposits you made",
    "withdrawal" => "Cash withdrawals", "fee" => "Bank fees", "card" => "Card purchase"
  }.freeze
  # Kinds that are one group whatever the line says, named for what they are.
  KIND_NAMES = { "transfer" => "Your own accounts", "check" => "Checks", "deposit" => "Deposits you made", "withdrawal" => "Cash withdrawals", "fee" => "Bank fees" }.freeze
  # Kinds a rule can't tell apart (no payee in the description).
  NO_RULE = %w[check].freeze
  # The plain name for a merchant the bank abbreviates.
  MERCHANTS = { "FACEBK" => "Facebook", "AMZN" => "Amazon", "AMAZON MKTPL" => "Amazon", "AMAZON.COM" => "Amazon", "EB" => "Eventbrite", "GOOGLE" => "Google", "UBER" => "Uber" }.freeze
  SMALL = %w[OF AND THE TO DE FOR].freeze
  KEEP = %w[NFP LLC INC LTD CO NA USA DBA].freeze
  # Two-letter words that are words, not initials like IL or BP.
  WORDS = %w[UP ON IN AT BY NO GO MY WE US DO IT].freeze
  # At the same count, the kinds that are an easy yes come first and checks last.
  ORDER = %w[transfer fee withdrawal deposit provider draft online card zelle_to zelle_from check].freeze
  LEADING_NOISE = /\A(?:POS DEBIT|DEBIT CARD PURCHASE|CARD PURCHASE|PURCHASE|RECURRING PAYMENT|PAYMENT TO|CHECKCARD \d+)\s+/i
  STATES = /\s+(?:AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY|DC)\z/

  Reading = Struct.new(:kind, :name, :phrase, :provider, keyword_init: true) do
    def kind_label = KINDS.fetch(kind)
    def rule? = !NO_RULE.include?(kind) && phrase.present?
    # Lines of this kind and name group together; the own-account kinds by kind alone.
    def group_key = KIND_NAMES.key?(kind) ? kind : "#{kind}:#{BankPayees.normalize(name)}"
  end

  Group = Struct.new(:key, :name, :kind, :direction, :lines, :phrases, :provider, keyword_init: true) do
    def kind_label = KINDS.fetch(kind)
    def rule? = !NO_RULE.include?(kind) && phrases.any?
    def count = lines.size
    def total_cents = lines.sum { |l| l.amount_cents.abs }
    def from = lines.map(&:on).min
    def to = lines.map(&:on).max
    def typical_cents = lines.map { |l| l.amount_cents.abs }.sort[lines.size / 2]
    def biggest_cents = lines.map { |l| l.amount_cents.abs }.max
    # The same amount most of the time: a wage, a subscription.
    def steady? = lines.size >= 4 && lines.map(&:amount_cents).tally.values.max >= lines.size * 0.6
    def per_week = (count / [ ((to - from).to_i + 1) / 7.0, 1 ].max).round(1)
    # Lines the matcher found something on the books for: a rule leaves them for the person.
    def suggested = lines.select(&:suggested?)
    def open = lines.select(&:open?)
    # What the bank calls it, each spelling with its count.
    def spellings = lines.group_by { |l| BankPayees.read(l.description).phrase }.map { |phrase, ls| [ phrase, ls.size ] }.sort_by { |_, n| -n }
  end

  class << self
    # The reading of one description.
    def read(description)
      text = description.to_s.strip.squeeze(" ")
      return Reading.new(kind: "check", name: "Checks", phrase: nil) if text.match?(/\ACHECK\b/i)
      return Reading.new(kind: "transfer", name: "Your own accounts", phrase: "Online Transfer") if text.match?(/\AOnline Transfer (?:to|from)\b/i)
      return Reading.new(kind: "withdrawal", name: "Cash withdrawals", phrase: "WITHDRAWAL") if text.match?(/\A(?:ATM )?WITHDRAWAL\b/i)
      if (m = text.match(/ORIG CO NAME:(.+?)\s+(?:ORIG ID|CO ENTRY|DESC DATE)/i))
        name = m[1].strip
        provider = text.match?(/IND ID:\s*ST-/i)
        return Reading.new(kind: (provider ? "provider" : "draft"), name: pretty(name), phrase: name, provider: provider)
      end
      if (m = text.match(/\AZelle payment (to|from) (.+)\z/i))
        words = m[2].split
        # The reference at the end: digits in it, or a bank's letter run (BACxbyclcxkb).
        words.pop while words.size > 1 && (words.last.match?(/\d/) || words.last.match?(/\A[A-Z]{3}[a-z0-9]{6,}\z/))
        name = words.join(" ")
        return Reading.new(kind: "zelle_#{m[1].downcase}", name: pretty(name), phrase: "#{m[1].downcase} #{name}")
      end
      if (m = text.match(/\AOnline (?:ACH )?Payment \d+ To (.+?)(?:\s+\(.*)?\s*\z/i))
        name = m[1].strip.sub(/\s+\d\d\/\d\d\z/, "")
        return Reading.new(kind: "online", name: pretty(name), phrase: "To #{name}")
      end
      return Reading.new(kind: "deposit", name: "Deposits you made", phrase: text[/\A[A-Za-z ]+/].to_s.strip.presence) if text.match?(/\bDEPOSIT\b/i)
      return Reading.new(kind: "fee", name: "Bank fees", phrase: text[/\A.*?\bFEES?\b/i]) if text.match?(/\bFEES?\b/i)

      card(text)
    end

    # A card purchase: the merchant is the text before the bank's own
    # reference (* or #), the phone number, the store number, the city
    # and state, and the date.
    def card(text)
      body = text.sub(LEADING_NOISE, "")
      if (m = body.match(/\ASQ \*(.+?)(?:\s+gosq\.com.*|\s+[A-Z]{2}\s+\d\d\/\d\d.*)?\z/i))
        name = m[1].strip
        return Reading.new(kind: "card", name: pretty(name), phrase: "SQ *#{name}")
      end
      cut = body.index(/\s*[*#]/)
      merchant = cut ? body[0, cut] : body
      merchant = merchant.sub(/\s+\d{3}-\d{3}-\d{4}.*\z/, "").sub(/\s+\d{3}-\d{7}.*\z/, "").sub(/\s+\S*\d{3,}\S*.*\z/, "")
      merchant = merchant.sub(/\s+\d\d\/\d\d\z/, "").sub(STATES, "").sub(/\s+\S+\.\S+\z/, "").strip
      merchant = body[0, cut + 1].strip if cut && merchant.size < 4
      merchant = body.split.first.to_s if merchant.blank?
      Reading.new(kind: "card", name: merchant_name(merchant), phrase: merchant)
    end

    # The lines waiting, grouped by payee: most lines first. A group is
    # every line with the same name going the same way (either way for the
    # organization's own transfers).
    def groups(organization, lines: organization.bank_statement_lines.to_deal_with.to_a)
      lines.group_by { |l| group_key_for(l) }.map do |key, ls|
        # Named the way the bank spells it most often.
        reading = ls.map { |l| read(l.description) }.group_by(&:name).max_by { |_, rs| rs.size }.last.first
        direction = reading.kind == "transfer" ? "any" : (ls.first.deposit? ? "in" : "out")
        # A provider's marker on money out is a vendor who bills through one, not a payout.
        kind = reading.kind == "provider" && direction == "out" ? "draft" : reading.kind
        Group.new(key: key, name: reading.name, kind: kind, direction: direction,
                  lines: ls.sort_by { |l| [ -l.on.jd, -l.id ] }, provider: (kind == "provider"),
                  phrases: ls.filter_map { |l| read(l.description).phrase }.uniq { |p| p.downcase })
      end.sort_by { |g| [ -g.count, ORDER.index(g.kind) || ORDER.size, g.name ] }
    end

    def group_key_for(line)
      reading = read(line.description)
      reading.kind == "transfer" ? "transfer" : "#{reading.group_key}:#{line.deposit? ? 'in' : 'out'}"
    end

    # Groups that look like the same payee spelled another way: the same
    # provider marker, a name one is a prefix of the other's, or a person
    # with the same surname and first initial. Offered, never merged.
    def siblings(group, groups)
      mine = normalize(group.name)
      groups.select do |other|
        next false if other.key == group.key || other.direction != group.direction
        next true if group.provider && other.provider

        theirs = normalize(other.name)
        if group.kind.start_with?("zelle") && other.kind == group.kind
          a = group.name.split
          b = other.name.split
          a.size > 1 && b.size > 1 && a.last.casecmp?(b.last) && a.first[0].casecmp?(b.first[0])
        else
          [ mine, theirs ].min_by(&:size).size >= 5 && (mine.start_with?(theirs) || theirs.start_with?(mine))
        end
      end
    end

    # Letters only, upcase, without the words that don't tell payees apart.
    # Letters only, so spellings meet; a payee with no letters (a Zelle to a
    # phone number) keeps its digits, so two numbers stay two payees.
    def normalize(name)
      up = name.to_s.upcase
      letters = up.sub(/\ATHE\s+/, "").gsub(/\b(?:COM|INC|LLC|LTD|CORP|CO)\b/, "").gsub(/[^A-Z]/, "")
      letters.presence || up.gsub(/[^A-Z0-9]/, "")
    end

    # ALL CAPS from the bank reads better as a name.
    def pretty(name)
      name = name.to_s.strip
      return name unless name == name.upcase

      name.split.each_with_index.map do |w, i|
        if SMALL.include?(w) && i.positive? then w.downcase
        elsif KEEP.include?(w) || w.size == 1 || (w.size == 2 && !WORDS.include?(w)) then w
        else w.capitalize
        end
      end.join(" ")
    end

    private

    def merchant_name(merchant)
      key = merchant.upcase.sub(/[#*]\z/, "").strip
      MERCHANTS[key] || MERCHANTS[key.split.first] || pretty(merchant.sub(/[#*]\z/, "").strip)
    end
  end
end
