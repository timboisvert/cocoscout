# frozen_string_literal: true

require "ostruct"

module Manage
  class DirectoryController < Manage::ManageController
    def index
      # Get filter params (prioritize params, fall back to session, then defaults)
      @sort = params[:sort] || session[:directory_sort] || "name_asc"
      @show = params[:show] || session[:directory_show] || "tiles"
      @filter = params[:filter] || session[:directory_filter] || (Current.production ? "current_production" : "everyone")
      @type = params[:type] || session[:directory_type] || "all"
      @search = params[:q] || ""

      # Validate values
      @show = "tiles" unless %w[tiles list].include?(@show)
      @filter = "everyone" unless %w[current_production org_talent_pools everyone].include?(@filter)
      @type = "all" unless %w[people groups all].include?(@type)
      @sort = "name_asc" unless %w[name_asc name_desc date_asc date_desc].include?(@sort)

      # Save to session (except search - that's transient)
      session[:directory_sort] = @sort
      session[:directory_show] = @show
      session[:directory_filter] = @filter
      session[:directory_type] = @type

      # Use service to build queries
      query_service = DirectoryQueryService.new(
        {
          sort: @sort,
          filter: @filter,
          type: @type,
          q: @search
        },
        Current.organization,
        Current.production
      )

      people, groups = query_service.call

      # ID-based pagination for heterogeneous collections
      # Step 1: Get IDs and sort fields only (lightweight query)
      people_data = people.pluck(:id, :name, :created_at)
                          .map { |id, name, created_at| { id: id, type: "Person", name: name, created_at: created_at } }
      groups_data = groups.pluck(:id, :name, :created_at)
                          .map { |id, name, created_at| { id: id, type: "Group", name: name, created_at: created_at } }

      all_entries_data = (people_data + groups_data)

      # Step 2: Sort in memory
      all_entries_data.sort_by! do |entry|
        case @sort
        when "name_asc"
          entry[:name].downcase
        when "name_desc"
          [ -1, entry[:name].downcase ]
        when "date_asc"
          entry[:created_at].to_i
        when "date_desc"
          -entry[:created_at].to_i
        end
      end

      # Reverse for descending name sort
      all_entries_data.reverse! if @sort == "name_desc"

      # Step 3: Paginate
      limit_per_page = 30
      page = (params[:page] || 1).to_i
      total_count = all_entries_data.length
      offset = (page - 1) * limit_per_page

      paginated_data = all_entries_data[offset, limit_per_page] || []

      # Step 4: Load full records with eager loading for just the paginated IDs
      person_ids = paginated_data.select { |e| e[:type] == "Person" }.map { |e| e[:id] }
      group_ids = paginated_data.select { |e| e[:type] == "Group" }.map { |e| e[:id] }

      loaded_people = Person
                      .includes(profile_headshots: { image_attachment: :blob })
                      .where(id: person_ids)
                      .index_by(&:id)
      loaded_groups = Group
                      .includes(profile_headshots: { image_attachment: :blob }, members: {})
                      .where(id: group_ids)
                      .index_by(&:id)

      # Step 5: Reconstruct entries in sorted order
      @entries = paginated_data.map do |entry_data|
        if entry_data[:type] == "Person"
          loaded_people[entry_data[:id]]
        else
          loaded_groups[entry_data[:id]]
        end
      end.compact

      # Create pagy-like object for pagination UI
      @pagy = OpenStruct.new(
        page: page,
        pages: (total_count.to_f / limit_per_page).ceil,
        count: total_count,
        limit: limit_per_page
      )

      # Calculate proper entity counts
      @people_count = people_data.count
      @groups_count = groups_data.count

      # Create email draft for the contact modal
      @email_draft = EmailDraft.new

      # Handle pagination with Turbo Streams for infinite scroll
      respond_to do |format|
        format.html # Normal page load
        format.turbo_stream # Infinite scroll requests
      end
    end

    def contact_directory
      person_ids = params[:person_ids]&.select(&:present?) || []
      @email_draft = EmailDraft.new(email_draft_params)
      subject = @email_draft.title
      body_html = @email_draft.body.to_s

      if person_ids.empty?
        redirect_to manage_directory_path, alert: "Please select at least one person or group."
        return
      end

      # Load people and groups from the IDs (scoped to current organization via HABTM)
      people = Current.organization.people.where(id: person_ids)
      groups = Current.organization.groups.where(id: person_ids)

      # Collect all people to email (direct people + group members with notifications enabled)
      people_to_email = []

      # Add directly selected people
      people_to_email.concat(people.to_a)

      # Add group members who have notifications enabled
      groups.each do |group|
        members_with_notifications = group.group_memberships.select(&:notifications_enabled?).map(&:person)
        people_to_email.concat(members_with_notifications)
      end

      # Remove duplicates
      people_to_email.uniq!

      # Send emails
      people_to_email.each do |person|
        Manage::ContactMailer.send_message(person, subject, body_html, Current.user).deliver_later
      end

      redirect_to manage_directory_path,
                  notice: "Email sent to #{people_to_email.count} #{'recipient'.pluralize(people_to_email.count)}."
    end

    def update_group_availability
      @group = Group.find(params[:id])
      updated_count = 0

      # Loop through all parameters looking for availability_Group_* keys
      params.each do |key, value|
        next unless key.start_with?("availability_Group_")

        show_id = key.split("_").last.to_i
        show = Show.find(show_id)
        availability = @group.show_availabilities.find_or_initialize_by(show: show)

        # Only update if the status has changed
        new_status = value
        current_status = if availability.available?
                           "available"
        elsif availability.unavailable?
                           "unavailable"
        end

        next unless new_status != current_status

        case new_status
        when "available"
          availability.available!
        when "unavailable"
          availability.unavailable!
        end

        availability.save
        updated_count += 1
      end

      if updated_count.positive?
        redirect_to manage_group_path(@group, tab: 2),
                    notice: "Availability updated for #{updated_count} #{'show'.pluralize(updated_count)}"
      else
        redirect_to manage_group_path(@group, tab: 2), alert: "No availability changes were made"
      end
    end

    private

    def email_draft_params
      params.require(:email_draft).permit(:title, :body)
    end
  end
end
