# frozen_string_literal: true

# Books starts with its categories (Tim, 2026-11-02): a few questions about
# the organization, and a recommended list of the built-in categories to
# say yes or no to, before anything else in Books. The answers are the
# organization's books_profile; every built-in category in
# config/money_categories.yml says which answers it is for (`for:`), and
# the ones the organization said no to go into money_categories_hidden,
# out of the pickers but never gone.
class BooksCategorySetup
  # What kind of organization: one answer, which stands for one or two flags.
  KINDS = {
    "venue" => { label: "A venue", description: "A space of our own, with shows in it: ours, and other people's", flags: %w[venue] },
    "company" => { label: "A performing company", description: "We make shows, in spaces we rent or share", flags: %w[company] },
    "both" => { label: "A venue with its own company", description: "Our space, our shows, and other people's shows too", flags: %w[venue company] },
    "school" => { label: "A school or studio", description: "Classes most of the time, with shows now and then", flags: %w[school classes] }
  }.freeze

  # The yes-or-no questions; each one is a flag of the same name.
  QUESTIONS = [
    [ "bar", "We sell drinks or snacks", "A bar, a concession stand, a cooler at the door" ],
    [ "merch", "We sell merchandise", "Shirts, posters, recordings" ],
    [ "classes", "We teach classes or workshops", "Courses, camps, drop-ins" ],
    [ "staff", "We have paid staff", "Door, bar, box office, crew on the clock" ],
    [ "pay_rent", "We pay rent for a space", "A lease, or a theater we rent by the night" ],
    [ "rent_out", "We rent our space to others", "Renters, co-productions, a share of their door" ],
    [ "nonprofit", "We are a nonprofit", "Grants, donations and memberships; the statements use nonprofit words" ]
  ].freeze

  FLAGS = (KINDS.values.flat_map { |k| k[:flags] } + QUESTIONS.map(&:first)).uniq.freeze

  # recommended: by the answers. offered: in the pickers now (not hidden;
  # everything is, before the setup). checked: how the setup page starts
  # it (what's offered once set up, the recommendation before).
  Category = Struct.new(:kind, :key, :label, :description, :for, :always, :recommended, :offered, :checked, keyword_init: true) do
    def id = "#{kind}:#{key}"
  end

  attr_reader :organization, :profile

  # profile: the answers, as saved or as submitted ({ "kind" => "venue", "bar" => "1" }).
  def initialize(organization, profile: nil)
    @organization = organization
    @profile = self.class.clean(profile || organization.books_profile)
  end

  # The answers, as flags: what the kind stands for, plus every yes.
  def flags
    kind = KINDS[profile["kind"]]
    ((kind ? kind[:flags] : []) + QUESTIONS.map(&:first).select { |q| profile[q] }).uniq
  end

  # Only the answers that mean anything, each yes as true.
  def self.clean(raw)
    raw = (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h).stringify_keys
    out = {}
    out["kind"] = raw["kind"] if KINDS.key?(raw["kind"])
    QUESTIONS.each { |q, _, _| out[q] = true if raw[q] == true || raw[q] == "1" }
    out
  end

  def answered? = profile.key?("kind")

  # Every built-in category, with whether the answers recommend it and
  # whether the organization offers it now.
  def categories
    @categories ||= %w[income spending].flat_map do |kind|
      list = kind == "income" ? MoneyCategories.income : MoneyCategories.spending
      list.map do |key, data|
        recommended = data["always"] || data["for"].nil? || (Array(data["for"]) & flags).any?
        offered = !organization.money_categories_hidden.include?("#{kind}:#{key}")
        Category.new(kind: kind, key: key, label: data["label"], description: data["description"], for: Array(data["for"]),
                     always: data["always"] == true, recommended: recommended, offered: offered,
                     checked: (organization.books_categories_set_up_at ? offered : recommended))
      end
    end
  end

  def income = categories.select { |c| c.kind == "income" }
  def spending = categories.select { |c| c.kind == "spending" }

  # The built-in categories to recommend for a set of answers, for the page
  # to turn on and off as the answers change: id => recommended.
  def recommendations = categories.to_h { |c| [ c.id, c.recommended ] }

  # Save the answers, what's offered, the organization's own categories,
  # and the acknowledgment. offered: the ids said yes to; custom: new
  # categories by kind ({ "income" => [ { "name" => ..., "description" => ... } ], "expense" => [...] });
  # a bare name does too.
  def save!(by:, offered:, custom: {})
    offered = Array(offered).map(&:to_s)
    hidden = categories.reject { |c| c.always || offered.include?(c.id) }.map(&:id)
    organization.transaction do
      organization.update!(books_profile: profile, money_categories_hidden: hidden, books_nonprofit: flags.include?("nonprofit"),
                           books_categories_set_up_at: organization.books_categories_set_up_at || Time.current,
                           books_categories_set_up_by: organization.books_categories_set_up_by || by)
      ChartOfAccounts.ensure!(organization)
      custom.to_h.each do |type, names|
        type = type.to_s == "income" ? "income" : "expense"
        Array(names).map { |n| n.respond_to?(:to_h) ? n.to_h.stringify_keys : { "name" => n } }
             .map { |n| [ n["name"].to_s.strip.squeeze(" "), n["description"].to_s.strip.presence ] }
             .reject { |name, _| name.blank? }.uniq(&:first).each do |name, description|
          next if organization.ledger_accounts.exists?(name: name, account_type: type)

          organization.ledger_accounts.create!(name: name, description: description, account_type: type, system: false, active: true, code: next_custom_code(type))
        end
      end
    end
    @categories = nil
    self
  end

  private

  def next_custom_code(type)
    base = type == "income" ? 4800 : 5800
    taken = organization.ledger_accounts.where("code >= ? AND code < ?", base.to_s, (base + 100).to_s).pluck(:code).map(&:to_i)
    ((base..(base + 99)).to_a - taken).first.to_s
  end
end
