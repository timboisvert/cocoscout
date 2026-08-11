# frozen_string_literal: true

module RuboCop
  module Cop
    module CocoScout
      # Flags `Model.find(params[...])` / `Model.find_by(id: params[...])` on a
      # bare constant inside manage controllers. Every hole in the Aug 2026
      # cross-org isolation audit was this exact shape: an org-owned record
      # looked up globally by an id the caller controls.
      #
      # Scope the lookup through the tenant instead:
      #
      #   # bad
      #   @group = Group.find(params[:id])
      #   @cycle = AuditionCycle.find_by(id: params[:cycle_id])
      #
      #   # good
      #   @group = Current.organization.groups.find(params[:id])
      #   @cycle = @production.audition_cycles.find(params[:cycle_id])
      #
      # Not flagged (receiver is already a scope, or the lookup is keyed by
      # something other than a caller-supplied id):
      #
      #   Current.organization.people.find(params[:person_id])
      #   @sign_up_form.sign_up_slots.find(params[:slot_id])
      #   PersonInvitation.find_by(token: params[:token])
      #   AuditionSession.find_by(id: params[:id], production: @production)
      #
      # A lookup that is genuinely platform-wide (an intentional cross-org
      # feature, or a model authorized some other way — e.g. Message threads
      # are gated per-user by `subscribed?`) gets an inline disable WITH a
      # justification comment, so every exception is visible and reviewed:
      #
      #   # Platform-wide by design: gated by subscribed? below.
      #   message = Message.find(params[:id]) # rubocop:disable CocoScout/UnscopedFind
      class UnscopedFind < Base
        MSG = "Unscoped %<method>s on %<model>s with caller-supplied id — scope through " \
              "Current.organization (or an already-scoped parent), or add an inline disable " \
              "with a comment justifying why this lookup is platform-wide."

        RESTRICT_ON_SEND = %i[find find_by find_by!].freeze

        # @!method const_find(node)
        def_node_matcher :const_find, <<~PATTERN
          (send $(const _ _) {:find :find_by :find_by!} $...)
        PATTERN

        def on_send(node)
          const_find(node) do |const_node, args|
            model = const_node.source
            next if allowed_receiver?(model)
            next unless offensive_args?(node.method_name, args)

            add_offense(node, message: format(MSG, method: node.method_name, model: model))
          end
        end

        private

        def offensive_args?(method_name, args)
          return false if args.empty?

          if method_name == :find
            args.any? { |arg| references_params?(arg) }
          else
            # find_by/find_by!: only a lookup keyed solely by a caller-supplied
            # id. Extra keys (production:, organization:) already scope it, and
            # non-id keys (token:, email:) are a different kind of lookup.
            hash = args.first
            return false unless hash&.hash_type?

            pairs = hash.pairs
            pairs.any? &&
              pairs.all? { |pair| pair.key.value == :id && references_params?(pair.value) }
          end
        end

        def references_params?(node)
          return false unless node.is_a?(RuboCop::AST::Node)
          return true if node.send_type? && node.receiver.nil? && node.method_name == :params

          node.each_descendant(:send).any? { |n| n.receiver.nil? && n.method_name == :params }
        end

        def allowed_receiver?(model)
          Array(cop_config["AllowedReceivers"]).include?(model.to_s)
        end
      end
    end
  end
end
