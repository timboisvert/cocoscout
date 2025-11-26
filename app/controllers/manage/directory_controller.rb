require "ostruct"

class Manage::DirectoryController < Manage::ManageController
  def index
    # Use params if provided, otherwise use defaults (ignore session for now to debug)
    @order = params[:order] || "alphabetical"
    @show = params[:show] || "tiles"
    @filter = params[:filter] || "everyone"
    @type = params[:type] || "all"

    # Validate values
    @show = "tiles" unless %w[tiles list].include?(@show)
    @filter = "everyone" unless %w[cast-members everyone].include?(@filter)
    @type = "all" unless %w[people groups all].include?(@type)

    # Save to session
    session[:directory_order] = @order
    session[:directory_show] = @show
    session[:directory_filter] = @filter
    session[:directory_type] = @type

    # Process the filter - scope to current production company
    if Current.organization
      people = Current.organization.people
      groups = Current.organization.groups
    else
      people = Person.all
      groups = Group.all
    end

    case @filter
    when "cast-members"
      people = people.joins(:talent_pools).distinct
      groups = groups.joins(:talent_pool_memberships).distinct
    when "everyone"
      people = people.all
      groups = groups.all
    else
      @filter = "everyone"
      people = people.all
      groups = groups.all
    end

    # Apply type filter
    case @type
    when "people"
      groups = Group.none
    when "groups"
      people = Person.none
    when "all"
      # Include both
    else
      @type = "all"
    end

    # Process the order and combine results
    people_query = people
    groups_query = groups

    case @order
    when "alphabetical"
      people_query = people_query.order(:name)
      groups_query = groups_query.order(:name)
    when "newest"
      people_query = people_query.order(created_at: :desc)
      groups_query = groups_query.order(created_at: :desc)
    when "oldest"
      people_query = people_query.order(created_at: :asc)
      groups_query = groups_query.order(created_at: :asc)
    else
      @order = "alphabetical"
      people_query = people_query.order(:name)
      groups_query = groups_query.order(:name)
    end

    # Combine and sort in memory since we can't paginate heterogeneous collections
    all_entries = (people_query.to_a + groups_query.to_a)

    case @order
    when "alphabetical"
      all_entries.sort_by!(&:name)
    when "newest"
      all_entries.sort_by! { |e| e.created_at }
      all_entries.reverse!
    when "oldest"
      all_entries.sort_by!(&:created_at)
    end

    limit_per_page = @show == "list" ? 12 : 24

    # Manual pagination
    page = (params[:page] || 1).to_i
    total_count = all_entries.length
    offset = (page - 1) * limit_per_page

    @entries = all_entries[offset, limit_per_page] || []

    # Create a simple pagy-like object for the view
    @pagy = OpenStruct.new(
      page: page,
      pages: (total_count.to_f / limit_per_page).ceil,
      count: total_count,
      limit: limit_per_page
    )
  end

  def show
    # Determine type from route and load the appropriate record
    if params[:type] == "person"
      @entry = Person.find(params[:id])

      # Get all future shows for productions this person is a cast member of
      production_ids = @entry.talent_pools.pluck(:production_id).uniq
      @shows = Show.where(production_id: production_ids, canceled: false)
                   .where("date_and_time >= ?", Time.current)
                   .order(:date_and_time)

      # Build a hash of availabilities: { show_id => show_availability }
      @availabilities = {}
      @entry.show_availabilities.where(show: @shows).each do |availability|
        @availabilities[availability.show_id] = availability
      end

      # Track edit mode
      @edit_mode = params[:edit] == "true"
    else
      @entry = Group.find(params[:id])

      # Get all future shows for productions this group is in a talent pool for
      production_ids = @entry.talent_pools.pluck(:production_id).uniq
      @shows = Show.where(production_id: production_ids, canceled: false)
                   .where("date_and_time >= ?", Time.current)
                   .order(:date_and_time)

      # Build a hash of availabilities: { show_id => show_availability }
      @availabilities = {}
      @entry.show_availabilities.where(show: @shows).each do |availability|
        @availabilities[availability.show_id] = availability
      end

      # Track edit mode
      @edit_mode = params[:edit] == "true"
    end

    render "show"
  end

  def update_group_availability
    @group = Group.find(params[:id])
    show = Show.find(params[:show_id])
    availability = @group.show_availabilities.find_or_initialize_by(show: show)

    if params[:status] == "available"
      availability.available!
    elsif params[:status] == "unavailable"
      availability.unavailable!
    end

    availability.save

    redirect_to params[:redirect_to] || manage_directory_group_path(@group, tab: 2, edit: "true")
  end
end
