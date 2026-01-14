# frozen_string_literal: true

module My
  class MessagesController < ApplicationController
    before_action :require_authentication
    before_action :load_forum_data

    def index
      @show_my_sidebar = true
      @filter = params[:filter] || "all"

      # Auto-select if only one forum
      if @sidebar_items.length == 1
        item = @sidebar_items.first
        if item[:type] == :organization
          @selected_organization = item[:object]
        else
          @selected_production = item[:object]
        end
      elsif params[:organization_id].present?
        @selected_organization = @my_organizations.find { |o| o.id == params[:organization_id].to_i }
      elsif params[:production_id].present?
        @selected_production = @sidebar_productions.find { |p| p.id == params[:production_id].to_i }
      elsif @sidebar_items.any?
        # Default to first item
        item = @sidebar_items.first
        if item[:type] == :organization
          @selected_organization = item[:object]
        else
          @selected_production = item[:object]
        end
      end

      # Load posts based on selection
      if @selected_organization
        org_productions = @all_productions.select { |p| p.organization_id == @selected_organization.id }
        posts_query = Post.where(production: org_productions)
                          .top_level
                          .includes(:author, :replies, :production, :rich_text_body)
                          .recent_first
        @posting_production = org_productions.first
      elsif @selected_production
        posts_query = Post.where(production: @selected_production)
                          .top_level
                          .includes(:author, :replies, :rich_text_body)
                          .recent_first
        @posting_production = @selected_production
      else
        posts_query = Post.none
      end

      # Apply filter
      if @filter == "unread" && posts_query.present?
        posts_query = posts_query.unviewed_by(Current.user)
      end

      @posts = posts_query.limit(50)

      # Mark posts as viewed when viewing "all"
      if @filter == "all" && @posts.any?
        @posts.each { |post| post.mark_viewed_by(Current.user) }
      end

      # Count unviewed posts for badge display
      @unviewed_counts = Post.where(production: @all_productions)
                             .top_level
                             .unviewed_by(Current.user)
                             .group(:production_id)
                             .count

      # Calculate total unread for current selection
      if @selected_organization
        org_production_ids = @all_productions.select { |p| p.organization_id == @selected_organization.id }.map(&:id)
        @current_unread_count = org_production_ids.sum { |id| @unviewed_counts[id] || 0 }
      elsif @selected_production
        @current_unread_count = @unviewed_counts[@selected_production.id] || 0
      else
        @current_unread_count = 0
      end

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def create
      @show_my_sidebar = true

      # Determine the production to post to
      production_id = params[:production_id]
      production = Production.find_by(id: production_id)

      unless production && @all_productions.include?(production)
        redirect_to my_messages_path, alert: "Production not found."
        return
      end

      @post = Post.new(post_params)
      @post.production = production
      @post.author = Current.user.person

      # Handle replies
      if params[:parent_id].present?
        parent_post = Post.find_by(id: params[:parent_id])
        if parent_post && parent_post.production_id == production.id
          @post.parent = parent_post
        end
      end

      if @post.save
        # Determine where to redirect based on forum mode
        org = production.organization
        if org.forum_shared?
          redirect_path = my_messages_path(organization_id: org.id)
        else
          redirect_path = my_messages_path(production_id: production.id)
        end

        respond_to do |format|
          format.turbo_stream {
            if @post.reply?
              # For replies, append to the replies section of the parent post
              render turbo_stream: turbo_stream.append("replies-for-#{@post.parent_id}", partial: "my/messages/post", locals: { post: @post, is_reply: true })
            else
              # For top-level posts, prepend to the posts list
              render turbo_stream: [
                turbo_stream.prepend("posts-list", partial: "my/messages/post", locals: { post: @post }),
                turbo_stream.update("new-post-form", partial: "my/messages/new_post_form", locals: { production: production })
              ]
            end
          }
          format.html { redirect_to redirect_path }
        end
      else
        respond_to do |format|
          format.turbo_stream {
            if @post.parent_id.present?
              # For reply errors, show error in the reply form
              render turbo_stream: turbo_stream.update("reply-form-#{@post.parent_id}", partial: "my/messages/reply_form", locals: { production: production, post: @post, parent_id: @post.parent_id })
            else
              # For top-level post errors, show error in the main form
              render turbo_stream: turbo_stream.update("new-post-form", partial: "my/messages/new_post_form", locals: { production: production, post: @post })
            end
          }
          format.html { redirect_to my_messages_path, alert: "Failed to create post." }
        end
      end
    end

    def emails
      @show_my_sidebar = true
      person = Current.user.person
      return redirect_to my_dashboard_path, alert: "No profile found." unless person

      # Load productions for the modal
      @my_productions = person.talent_pool_productions
                              .includes(:organization, logo_attachment: :blob)
                              .order(:name)

      # Get emails sent to this person (across all organizations)
      email_logs_query = EmailLog.for_recipient_entity(person).recent

      if params[:search].present?
        search_term = "%#{params[:search]}%"
        email_logs_query = email_logs_query.where("subject ILIKE ?", search_term)
      end

      @email_logs_pagy, @email_logs = pagy(email_logs_query.includes(:production), limit: 20)
      @search_query = params[:search]

      # For the send message modal - create empty email draft
      @email_draft = EmailDraft.new
    end

    def show
      @show_my_sidebar = true
      person = Current.user.person
      return redirect_to my_dashboard_path, alert: "No profile found." unless person

      @email_log = EmailLog.for_recipient_entity(person).find_by(id: params[:id])

      unless @email_log
        redirect_to my_messages_path, alert: "Message not found."
      end
    end

    def send_message
      production_id = params[:production_id]
      @email_draft = EmailDraft.new(email_draft_params)
      subject = @email_draft.title
      body_html = @email_draft.body.to_s

      production = Production.find_by(id: production_id)

      # Prepare variables for the template
      template_vars = {
        sender_name: Current.user.person.name,
        sender_email: Current.user.person.email,
        production_name: production&.name,
        body_html: body_html,
        subject: subject
      }

      # Render subject and body using the passthrough template
      rendered_subject = EmailTemplateService.render_subject("talent_pool_message", template_vars)
      rendered_body = EmailTemplateService.render_body("talent_pool_message", template_vars)

      if production_id.blank?
        redirect_back fallback_location: my_messages_emails_path, alert: "Please select a production to contact."
        return
      end

      unless production
        redirect_back fallback_location: my_messages_emails_path, alert: "Production not found."
        return
      end

      # Verify the user is in the talent pool of this production
      unless Current.user.person.in_talent_pool_for?(production)
        redirect_back fallback_location: my_messages_emails_path, alert: "You are not a member of this production's talent pool."
        return
      end

      # Send to production email address
      production_email = production.contact_email
      if production_email.blank?
        redirect_back fallback_location: my_messages_emails_path, alert: "This production does not have a contact email address configured."
        return
      end


      # Send the email to the production
      My::TalentMessageMailer.send_to_production(
        sender: Current.user.person,
        production: production,
        subject: rendered_subject,
        body_html: rendered_body
      ).deliver_later

      redirect_back fallback_location: my_production_path(production, tab: 2),
                    notice: "Message sent to #{production.name} team."
    end

    private

    def load_forum_data
      return redirect_to my_dashboard_path, alert: "No profile found." unless Current.user.person

      # Get all productions the user is in the talent pool of
      @all_productions = Current.user.person.talent_pool_productions
                                      .where(forum_enabled: true)
                                      .includes(:organization, logo_attachment: :blob)
                                      .order(:name)

      # Group by organization and determine what to show in sidebar
      @sidebar_productions = []
      @my_organizations = []
      @sidebar_items = []

      productions_by_org = @all_productions.group_by(&:organization)

      productions_by_org.each do |org, productions|
        if org.forum_shared?
          # Shared mode: show organization in sidebar (not individual productions)
          @my_organizations << org
          @sidebar_items << { type: :organization, object: org, name: org.name }
        else
          # Per-production mode: show individual productions
          productions.each do |production|
            @sidebar_productions << production
            @sidebar_items << { type: :production, object: production, name: production.name }
          end
        end
      end

      @my_organizations.uniq!
      @sidebar_items.sort_by! { |item| item[:name].downcase }
    end

    def post_params
      params.require(:post).permit(:body)
    end

    def email_draft_params
      params.require(:email_draft).permit(:title, :body)
    end
  end
end
