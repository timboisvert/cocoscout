# frozen_string_literal: true

namespace :routes do
  desc "Validate that all URL/path helpers used in views exist as actual routes"
  task validate_helpers: :environment do
    require "set"

    # Load all routes to get valid helper names
    Rails.application.reload_routes!
    valid_helpers = Set.new

    Rails.application.routes.routes.each do |route|
      name = route.name
      next unless name.present?

      valid_helpers << "#{name}_path"
      valid_helpers << "#{name}_url"
    end

    # Also add rails built-in helpers
    valid_helpers << "rails_blob_path"
    valid_helpers << "rails_blob_url"
    valid_helpers << "rails_storage_redirect_path"
    valid_helpers << "rails_storage_redirect_url"
    valid_helpers << "rails_storage_proxy_path"
    valid_helpers << "rails_storage_proxy_url"
    valid_helpers << "rails_representation_path"
    valid_helpers << "rails_representation_url"
    valid_helpers << "polymorphic_path"
    valid_helpers << "polymorphic_url"

    # Pattern to match URL/path helper calls in ERB files
    # Matches: helper_name( or helper_name(@ or helper_name(@var, etc.
    helper_pattern = /\b([a-z_]+(?:_path|_url))\s*\(/

    errors = []
    view_files = Dir.glob(Rails.root.join("app/views/**/*.erb"))

    view_files.each do |file|
      content = File.read(file)
      line_number = 0

      content.each_line do |line|
        line_number += 1
        line.scan(helper_pattern) do |match|
          helper_name = match[0]

          # Skip dynamic/interpolated helpers and common non-route helpers
          next if helper_name.start_with?("safe_")
          next if %w[image_path asset_path font_path].include?(helper_name)

          unless valid_helpers.include?(helper_name)
            relative_path = Pathname.new(file).relative_path_from(Rails.root)
            errors << {
              file: relative_path.to_s,
              line: line_number,
              helper: helper_name,
              context: line.strip[0..100]
            }
          end
        end
      end
    end

    if errors.empty?
      puts "\n✅ All #{view_files.size} view files have valid route helpers!\n\n"
    else
      puts "\n❌ Found #{errors.size} invalid route helper(s):\n\n"

      errors.each do |error|
        puts "  #{error[:file]}:#{error[:line]}"
        puts "    Helper: #{error[:helper]}"
        puts "    Context: #{error[:context]}"
        puts ""
      end

      # Suggest similar valid helpers
      errors.map { |e| e[:helper] }.uniq.each do |invalid_helper|
        similar = valid_helpers.select { |h| similar_helper?(h, invalid_helper) }.first(3)
        if similar.any?
          puts "  💡 Did you mean one of these for '#{invalid_helper}'?"
          similar.each { |s| puts "     - #{s}" }
          puts ""
        end
      end

      exit 1
    end
  end

  def similar_helper?(valid, invalid)
    # Simple similarity check - shares significant parts
    valid_parts = valid.gsub(/_path|_url/, "").split("_")
    invalid_parts = invalid.gsub(/_path|_url/, "").split("_")

    shared = valid_parts & invalid_parts
    shared.size >= [valid_parts.size, invalid_parts.size].min * 0.6
  end
end
