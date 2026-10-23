# frozen_string_literal: true

module Manage
  # Segments: followers picked by what they did, with a live count as the
  # rules change (count).
  class SegmentsController < ManageController
    before_action :set_segment, only: %i[show update destroy]

    def new
      @segment = Current.organization.segments.new(rule: { "match" => "all", "conditions" => [ { "type" => "bought", "target" => "any" } ] })
      load_choices
    end

    def create
      @segment = Current.organization.segments.new(name: params.dig(:segment, :name), rule: rule_from_params)
      if @segment.save
        redirect_to manage_segment_path(@segment), notice: "Saved. It keeps itself current."
      else
        load_choices
        flash.now[:alert] = @segment.errors.full_messages.to_sentence
        render :new, status: :unprocessable_content
      end
    end

    def show
      load_choices
    end

    def update
      if @segment.update(name: params.dig(:segment, :name), rule: rule_from_params)
        redirect_to manage_segment_path(@segment), notice: "Saved."
      else
        load_choices
        flash.now[:alert] = @segment.errors.full_messages.to_sentence
        render :show, status: :unprocessable_content
      end
    end

    def destroy
      @segment.destroy!
      redirect_to manage_mailing_lists_path, notice: "#{@segment.name} is deleted. Nobody on your lists was touched."
    end

    # How many the rules pick right now, and a few of them.
    def count
      followers = SegmentQuery.new(Current.organization, rule_from_params).followers.subscribed
      sample = followers.order(updated_at: :desc).limit(4).map { |f| { name: f.display_name, email: f.email } }
      render json: { count: followers.count, sample: sample }
    end

    private

    def set_segment
      @segment = Current.organization.segments.find(params[:id])
    end

    def rule_from_params
      rows = params[:conditions].respond_to?(:to_unsafe_h) ? params[:conditions].to_unsafe_h.values : Array(params[:conditions])
      conditions = rows.filter_map do |row|
        row = row.to_h.stringify_keys.slice("type", "target", "count", "when", "date", "list_id", "kind")
        row if Segment::CONDITION_TYPES.include?(row["type"])
      end
      { "match" => params[:match] == "any" ? "any" : "all", "conditions" => conditions }
    end

    def load_choices
      @lists = Current.organization.mailing_lists.active.main_first.to_a
      @productions = Current.organization.productions.active.where.not(production_type: "course").order(:name).to_a
      @targets = [ [ "Anything", "any" ], [ "An in-house production", "type:in_house" ], [ "A contract production", "type:third_party" ] ] +
                 @lists.reject(&:main?).map { |list| [ "Any of #{list.name}", "list:#{list.id}" ] } +
                 @productions.map { |production| [ production.name, "production:#{production.id}" ] }
    end
  end
end
