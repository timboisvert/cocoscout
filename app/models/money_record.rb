# frozen_string_literal: true

# Money recorded by hand (Money → Books → Record money): a sponsor's check,
# a receipt, door cash deposited. One record is one "recorded" entry on the
# books; changing it restates the entry and removing it reverses it, so
# history is never edited.
#
#   in:   via account ↑ / income category ↑
#   out:  spending category ↑ / via account ↓
#   move: to ↑ / from ↓
class MoneyRecord < ApplicationRecord
  KINDS = %w[in out move].freeze

  # A new record of one kind, with the form's starting choices: today, from
  # the bank, door cash deposited to the bank.
  def self.blank_for(organization, kind)
    organization.money_records.new(kind: kind, on: Date.current, via: "bank", from_account: "door_cash", to_account: "bank")
  end

  # Where money came from or went, in the words the sheet uses. The
  # "owed" choices don't move cash: money in that's still owed sits as
  # money owed to you; money out that someone covered sits as money you owe.
  VIA = {
    "in" => { "bank" => [ "Bank", :bank ], "door_cash" => [ "Door cash", :door_cash ], "owed" => [ "Not yet (they still owe it)", :owed_to_you ] },
    "out" => { "bank" => [ "Bank", :bank ], "card" => [ "Credit card", :credit_card ], "door_cash" => [ "Door cash", :door_cash ],
               "owed" => [ "Someone's own money, to pay back", :you_owe ] }
  }.freeze
  MOVE_ACCOUNTS = { "bank" => [ "Bank", :bank ], "door_cash" => [ "Door cash", :door_cash ], "credit_card" => [ "Credit card", :credit_card ] }.freeze

  include BooksLock::Validation
  refuses_locked_books_on :on

  belongs_to :organization
  belongs_to :production, optional: true
  belongs_to :show, optional: true
  belongs_to :recorded_by, class_name: "User", optional: true

  has_one_attached :receipt
  include HierarchicalStorageKey # after the attachment, so the key moves once the file is up

  validates :kind, inclusion: { in: KINDS }
  validates :on, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :category_key, presence: true, if: -> { kind.in?(%w[in out]) }
  validates :via, inclusion: { in: ->(r) { VIA.fetch(r.kind, {}).keys } }, if: -> { kind.in?(%w[in out]) }
  validates :from_account, :to_account, inclusion: { in: MOVE_ACCOUNTS.keys }, if: -> { kind == "move" }
  validate :move_between_different_accounts
  validate :show_belongs_to_production
  validate :acceptable_receipt

  after_commit :post_to_books, on: %i[create update]
  after_commit :unpost_from_books, on: :destroy

  scope :recent, -> { order(on: :desc, id: :desc) }

  def in? = kind == "in"
  def out? = kind == "out"
  def move? = kind == "move"

  def amount = amount_cents / 100.0

  def amount=(value)
    self.amount_cents = value.to_s.delete(",$ ").to_d.round(2).then { |d| (d * 100).to_i }
  end

  def category_label
    return nil if move?

    MoneyCategories.label_for(category_key, in? ? :income : :spending, organization: organization)
  end

  def category_account
    MoneyCategories.account_for(category_key, in? ? :income : :spending, organization: organization)
  end

  def via_label = VIA.dig(kind, via, 0)
  def via_account = VIA.dig(kind, via, 1)
  def from_label = MOVE_ACCOUNTS.dig(from_account, 0)
  def to_label = MOVE_ACCOUNTS.dig(to_account, 0)

  # "Sponsorship · Logan Square Chamber", the way Entries names it.
  def title
    case kind
    when "move" then "#{from_label} to #{to_label}"
    else [ category_label, counterparty.presence ].compact.join(" · ")
    end
  end

  def kind_label
    { "in" => "Money in", "out" => "Money out", "move" => "Moved between your accounts" }.fetch(kind)
  end

  def for_label
    return nil unless production

    show ? "#{production.name}, #{show.date_and_time.strftime('%b %-d, %Y')}" : "#{production.name}, the whole production"
  end

  def journal_entry
    JournalEntry.live.find_by(source_type: self.class.polymorphic_name, source_id: id, kind: "recorded")
  end

  def journal_entries
    JournalEntry.where(source_type: self.class.polymorphic_name, source_id: id, kind: "recorded").order(:posted_at)
  end

  def lines
    dims = { production: production, show: show }
    case kind
    when "in" then [ { account: via_account, amount_cents: amount_cents }.merge(dims), { account: category_account, amount_cents: -amount_cents }.merge(dims) ]
    when "out" then [ { account: category_account, amount_cents: amount_cents }.merge(dims), { account: via_account, amount_cents: -amount_cents }.merge(dims) ]
    when "move" then [ { account: MOVE_ACCOUNTS.fetch(to_account)[1], amount_cents: amount_cents }, { account: MOVE_ACCOUNTS.fetch(from_account)[1], amount_cents: -amount_cents } ]
    end
  end

  def post_to_books
    LedgerPosting.post!(organization: organization, source: self, kind: "recorded", entry_date: on, cash_date: cash_date,
                        memo: title, lines: lines)
  end

  def unpost_from_books
    LedgerPosting.unpost!(source: self, kind: "recorded")
  end

  private

  # Money that's still owed hasn't moved; it shows up on a cash basis when
  # it's paid (recorded again, or matched on the bank page).
  def cash_date
    via == "owed" ? nil : on
  end

  def move_between_different_accounts
    errors.add(:to_account, "must be a different account") if move? && from_account.present? && from_account == to_account
  end

  def show_belongs_to_production
    return if show.nil?

    self.production ||= show.production
    errors.add(:show, "is not part of that production") if production && show.production_id != production.id
  end

  def acceptable_receipt
    return unless receipt.attached?

    errors.add(:receipt, "must be a PDF, JPG or PNG") unless receipt.content_type.in?(%w[application/pdf image/jpeg image/png])
    errors.add(:receipt, "must be under 10 MB") if receipt.byte_size > 10.megabytes
  end
end
