# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require Rails.root.join("lib/rubocop/cop/cocoscout/unscoped_find")

RSpec.describe RuboCop::Cop::CocoScout::UnscopedFind, :config do
  let(:config) do
    RuboCop::Config.new(
      "CocoScout/UnscopedFind" => { "AllowedReceivers" => [ "QuestionTypes::Base" ] }
    )
  end

  it "flags Model.find with a params id" do
    expect_offense(<<~RUBY)
      @group = Group.find(params[:id])
               ^^^^^^^^^^^^^^^^^^^^^^^ Unscoped find on Group with caller-supplied id — scope through Current.organization (or an already-scoped parent), or add an inline disable with a comment justifying why this lookup is platform-wide.
    RUBY
  end

  it "flags find_by(id: params[...])" do
    expect_offense(<<~RUBY)
      @g = Group.find_by(id: params[:group_id])
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Unscoped find_by on Group with caller-supplied id — scope through Current.organization (or an already-scoped parent), or add an inline disable with a comment justifying why this lookup is platform-wide.
    RUBY
  end

  it "flags a namespaced constant" do
    expect_offense(<<~RUBY)
      x = Manage::Thing.find(params[:id])
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Unscoped find on Manage::Thing with caller-supplied id — scope through Current.organization (or an already-scoped parent), or add an inline disable with a comment justifying why this lookup is platform-wide.
    RUBY
  end

  it "does not flag a lookup scoped through a receiver chain" do
    expect_no_offenses("@group = Current.organization.groups.find(params[:id])")
    expect_no_offenses("@slot = @sign_up_form.sign_up_slots.find(params[:slot_id])")
  end

  it "does not flag find_by keyed on a non-id column" do
    expect_no_offenses("PersonInvitation.find_by(token: params[:token])")
  end

  it "does not flag find_by that also scopes by another column" do
    expect_no_offenses("AuditionSession.find_by(id: params[:id], production: @production)")
  end

  it "does not flag a find whose argument is not params-derived" do
    expect_no_offenses("Group.find(some_local_id)")
    expect_no_offenses("Group.find(1)")
  end

  it "does not flag an allowlisted (non-AR) receiver" do
    expect_no_offenses("type_class = QuestionTypes::Base.find(params[:question_type])")
  end

  it "does not flag find on a non-constant receiver" do
    expect_no_offenses("collection.find { |x| x.id == params[:id] }")
  end
end
