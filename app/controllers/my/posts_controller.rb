# frozen_string_literal: true

module My
  class PostsController < ApplicationController
    before_action :require_superadmin_for_beta
    before_action :set_production, only: [ :index, :create ]
    before_action :set_post, only: [ :destroy, :create_reply ]
    before_action :authorize_production_access, only: [ :index, :create ]
    before_action :authorize_post_access, only: [ :destroy, :create_reply ]

    def index
      @posts = @production.posts
                          .top_level
                          .recent_first
                          .includes(:author, :replies)
                          .limit(50)

      @new_post = @production.posts.build

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def create
      @post = @production.posts.build(post_params)
      @post.author = posting_author

      if @post.save
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to my_production_posts_path(@production), notice: "Post created." }
        end
      else
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.replace("new_post_form", partial: "my/posts/form", locals: { post: @post, production: @production }) }
          format.html { render :index, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @production = @post.production

      if @post.author == posting_author || can_moderate?
        @post.destroy
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.remove(@post) }
          format.html { redirect_to my_production_posts_path(@production), notice: "Post deleted." }
        end
      else
        respond_to do |format|
          format.turbo_stream { head :forbidden }
          format.html { redirect_to my_production_posts_path(@production), alert: "You can only delete your own posts." }
        end
      end
    end

    def create_reply
      @production = @post.production
      @reply = @production.posts.build(post_params)
      @reply.author = posting_author
      @reply.parent = @post

      if @reply.save
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to my_production_posts_path(@production), notice: "Reply posted." }
        end
      else
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.replace("reply_form_#{@post.id}", partial: "my/posts/reply_form", locals: { post: @post, reply: @reply }) }
          format.html { redirect_to my_production_posts_path(@production), alert: "Reply could not be posted." }
        end
      end
    end

    private

    def set_production
      @production = Production.find(params[:production_id])
    end

    def set_post
      @post = Post.find(params[:id])
    end

    def post_params
      params.require(:post).permit(:body, images: [])
    end

    # Determine who is posting - the user's primary person profile
    def posting_author
      Current.user.person
    end

    # Check if user has access to this production
    def authorize_production_access
      return if has_production_access?(@production)

      redirect_to my_productions_path, alert: "You don't have access to this production's message board."
    end

    def authorize_post_access
      @production = @post.production
      return if has_production_access?(@production)

      redirect_to my_productions_path, alert: "You don't have access to this post."
    end

    # User has access if they are:
    # 1. In the talent pool (via person or group)
    # 2. A production team member
    # 3. An organization manager/viewer
    def has_production_access?(production)
      talent_pool_access?(production) ||
        production_team_access?(production) ||
        organization_access?(production)
    end

    def talent_pool_access?(production)
      people_ids = Current.user.people.active.pluck(:id)
      group_ids = Group.active
                       .joins(:group_memberships)
                       .where(group_memberships: { person_id: people_ids })
                       .pluck(:id)

      talent_pool = production.effective_talent_pool
      return false unless talent_pool

      TalentPoolMembership.exists?(talent_pool: talent_pool, member_type: "Person", member_id: people_ids) ||
        (group_ids.any? && TalentPoolMembership.exists?(talent_pool: talent_pool, member_type: "Group", member_id: group_ids))
    end

    def production_team_access?(production)
      ProductionPermission.exists?(production: production, user: Current.user)
    end

    def organization_access?(production)
      OrganizationPermission.exists?(organization: production.organization, user: Current.user)
    end

    # Moderators can delete any post
    def can_moderate?
      production_team_access?(@production) || organization_access?(@production)
    end

    # Beta feature - restrict to superadmins only
    def require_superadmin_for_beta
      return if Current.user.superadmin?

      redirect_to my_dashboard_path, alert: "This feature is currently in beta."
    end
  end
end
