# frozen_string_literal: true

# One change to one or more dates (Tim, 2026-11-27, "Cancel or move this
# date"): canceling them, moving them, deleting them, or bringing canceled
# ones back. While the manager goes through the steps it's a draft holding
# what they chose (which dates, where they go, what happens to each thing
# they touch). Applying it (ShowChangePlan::Apply) does all of it, one step
# at a time, and keeps the record: each step's progress, anything CocoScout
# couldn't finish, and what bringing the dates back would need (undo).
#
#   show_ids       the dates chosen (cancel, move, restore, delete)
#   also_show_ids  the events tied to them, or the same night, chosen too
#   move           where a move goes: starts_at, ends_at, location, space,
#                  the series rule, per-date choices, a contract's rental times
#   choices        what happens to each thing touched, with any edited words
#   steps          [{ key, label, status, detail, done_at, counts }]
#   problems       [{ key, kind, label, detail, order_id/person_id, status }]
class DateChange < ApplicationRecord
  KINDS = %w[cancel move delete restore].freeze
  STATUSES = %w[draft applying applied].freeze
  SCOPES = %w[this following chosen].freeze

  belongs_to :organization
  belongs_to :production, optional: true
  belongs_to :show, optional: true
  belongs_to :contract, optional: true
  belongs_to :contract_date_request, optional: true
  belongs_to :created_by_user, class_name: "User", optional: true
  belongs_to :restores, class_name: "DateChange", optional: true
  has_many :restorations, class_name: "DateChange", foreign_key: :restores_id, dependent: :nullify, inverse_of: :restores

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :drafts, -> { where(status: "draft") }
  scope :applied, -> { where.not(status: "draft") }

  KINDS.each { |k| define_method(:"#{k}?") { kind == k } }
  def draft? = status == "draft"
  def applied? = !draft?

  # The dates in the change: the chosen ones first, then the events chosen
  # with them, each in date order. Only this organization's.
  def main_shows = scoped_shows(show_ids)
  def also_shows = scoped_shows(also_show_ids)
  def shows = (main_shows + also_shows).uniq.sort_by(&:date_and_time)
  def all_show_ids = (show_ids + also_show_ids).map(&:to_i).uniq

  def choice(key, default = nil)
    value = choices.fetch(key.to_s, nil)
    value.nil? ? default : value
  end

  # A toggle the manager left on (or never touched, when it's on by default).
  def on?(key, default: true)
    value = choice(key)
    return default if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def step(key) = steps.find { |s| s["key"] == key.to_s }

  # Sets a step's state and saves it at once, so the record page shows it
  # as it happens. Reloads first: the refunds job writes its own step.
  def mark_step!(key, label: nil, status: "done", detail: nil, **extra)
    with_lock do
      list = steps.map(&:dup)
      entry = list.find { |s| s["key"] == key.to_s }
      unless entry
        entry = { "key" => key.to_s }
        list << entry
      end
      entry["label"] = label if label
      entry["status"] = status
      entry["detail"] = detail if detail
      entry["done_at"] = Time.current.iso8601 if status.in?(%w[done problem])
      extra.each { |k, v| entry[k.to_s] = v }
      update_columns(steps: list, updated_at: Time.current)
    end
  end

  def add_problem!(key:, kind:, label:, detail: nil, **extra)
    with_lock do
      list = problems.reject { |p| p["key"] == key.to_s }
      list << { "key" => key.to_s, "kind" => kind.to_s, "label" => label, "detail" => detail, "status" => "open" }.merge(extra.stringify_keys)
      update_columns(problems: list, updated_at: Time.current)
    end
  end

  def resolve_problem!(key, status: "resolved", by: nil)
    with_lock do
      list = problems.map do |p|
        next p unless p["key"] == key.to_s

        p.merge("status" => status, "resolved_at" => Time.current.iso8601, "resolved_by_user_id" => by&.id)
      end
      update_columns(problems: list, updated_at: Time.current)
    end
  end

  def open_problems = problems.select { |p| p["status"] == "open" }
  def steps_done = steps.count { |s| s["status"].in?(%w[done problem]) }
  def finished? = applied? && steps.all? { |s| s["status"].in?(%w[done problem]) }
  def unfinished? = applied? && (!finished? || open_problems.any?)

  # The dates a cancel took off that are still canceled (what Bring back
  # can offer).
  def still_canceled_shows = shows.select(&:canceled?)

  private

  def scoped_shows(ids)
    ids = Array(ids).map(&:to_i).uniq
    return [] if ids.empty?

    Show.joins(:production).where(productions: { organization_id: organization_id }, id: ids)
        .includes(:production, :location, :location_space).order(:date_and_time).to_a
  end
end
