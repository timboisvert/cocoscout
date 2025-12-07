# frozen_string_literal: true

namespace :cache do
  desc "Run comprehensive cache diagnostics to assess health, performance, and opportunities"
  task diagnostics: :environment do
    CacheDiagnostics.run
  end

  desc "Run quick cache health check (safe for frequent use)"
  task health: :environment do
    CacheDiagnostics.health_check
  end

  desc "Benchmark cache read/write performance"
  task benchmark: :environment do
    CacheDiagnostics.benchmark
  end
end

class CacheDiagnostics
  class << self
    def run
      puts "\n#{'=' * 70}"
      puts "CACHE DIAGNOSTICS REPORT"
      puts "Generated: #{Time.current}"
      puts "Environment: #{Rails.env}"
      puts "#{'=' * 70}\n\n"

      check_cache_store_config
      check_solid_cache_stats
      check_cache_connectivity
      benchmark_operations
      analyze_cache_keys
      check_fragment_cache_usage
      provide_recommendations

      puts "\n#{'=' * 70}"
      puts "END OF REPORT"
      puts "#{'=' * 70}\n"
    end

    def health_check
      puts "\n📊 Quick Cache Health Check"
      puts "-" * 40

      # Test basic connectivity
      test_key = "health_check_#{SecureRandom.hex(4)}"
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        Rails.cache.write(test_key, "ok", expires_in: 1.minute)
        result = Rails.cache.read(test_key)
        Rails.cache.delete(test_key)
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)

        if result == "ok"
          puts "✅ Cache is operational (round-trip: #{elapsed}ms)"
        else
          puts "⚠️  Cache write succeeded but read returned: #{result.inspect}"
        end
      rescue StandardError => e
        puts "❌ Cache error: #{e.message}"
      end

      # Show Solid Cache stats if available
      if solid_cache_available?
        stats = solid_cache_stats
        puts "\n📈 Solid Cache Stats:"
        puts "   Entries: #{format_number(stats[:entry_count])}"
        puts "   Size: #{format_bytes(stats[:total_bytes])} / #{format_bytes(max_cache_size)}"
        puts "   Usage: #{stats[:usage_percent]}%"

        if stats[:oldest_entry]
          age = time_ago_in_words(stats[:oldest_entry])
          puts "   Oldest entry: #{age} ago"
        end
      end

      puts "-" * 40
    end

    def benchmark
      puts "\n⏱️  Cache Performance Benchmark"
      puts "-" * 40

      results = {}

      # Small payload
      small_data = { id: 1, name: "test" }
      results[:small_write] = benchmark_operation("Small write (100 bytes)") do
        Rails.cache.write("bench_small", small_data, expires_in: 1.minute)
      end
      results[:small_read] = benchmark_operation("Small read") do
        Rails.cache.read("bench_small")
      end

      # Medium payload
      medium_data = { items: Array.new(100) { |i| { id: i, name: "Item #{i}", data: "x" * 100 } } }
      results[:medium_write] = benchmark_operation("Medium write (~15KB)") do
        Rails.cache.write("bench_medium", medium_data, expires_in: 1.minute)
      end
      results[:medium_read] = benchmark_operation("Medium read") do
        Rails.cache.read("bench_medium")
      end

      # Large payload
      large_data = { items: Array.new(1000) { |i| { id: i, name: "Item #{i}", data: "x" * 500 } } }
      results[:large_write] = benchmark_operation("Large write (~600KB)") do
        Rails.cache.write("bench_large", large_data, expires_in: 1.minute)
      end
      results[:large_read] = benchmark_operation("Large read") do
        Rails.cache.read("bench_large")
      end

      # Fetch (miss + write)
      Rails.cache.delete("bench_fetch")
      results[:fetch_miss] = benchmark_operation("Fetch (cache miss)") do
        Rails.cache.fetch("bench_fetch", expires_in: 1.minute) { small_data }
      end

      # Fetch (hit)
      results[:fetch_hit] = benchmark_operation("Fetch (cache hit)") do
        Rails.cache.fetch("bench_fetch", expires_in: 1.minute) { small_data }
      end

      # Multi-read
      keys = 10.times.map { |i| "bench_multi_#{i}" }
      keys.each { |k| Rails.cache.write(k, small_data, expires_in: 1.minute) }
      results[:multi_read] = benchmark_operation("Multi-read (10 keys)") do
        Rails.cache.read_multi(*keys)
      end

      # Cleanup
      %w[bench_small bench_medium bench_large bench_fetch].each { |k| Rails.cache.delete(k) }
      keys.each { |k| Rails.cache.delete(k) }

      puts "\n📊 Summary:"
      puts "   Avg small read:  #{results[:small_read][:avg].round(2)}ms"
      puts "   Avg medium read: #{results[:medium_read][:avg].round(2)}ms"
      puts "   Avg large read:  #{results[:large_read][:avg].round(2)}ms"
      puts "   Fetch hit vs miss speedup: #{(results[:fetch_miss][:avg] / results[:fetch_hit][:avg]).round(1)}x"

      puts "-" * 40
    end

    private

    def check_cache_store_config
      puts "📦 CACHE STORE CONFIGURATION"
      puts "-" * 40

      store = Rails.cache
      store_class = store.class.name

      puts "Store type: #{store_class}"

      case store_class
      when /SolidCache/
        puts "Backend: SQLite/PostgreSQL (Solid Cache)"
        puts "Namespace: #{store.options[:namespace] || '(none)'}"
        puts "Max size: #{format_bytes(max_cache_size)}"
      when /MemoryStore/
        puts "Backend: In-process memory"
        puts "⚠️  Warning: Not suitable for production with multiple processes"
      when /RedisCache/
        puts "Backend: Redis"
      when /MemCacheStore/
        puts "Backend: Memcached"
      when /NullStore/
        puts "Backend: Null store (caching disabled)"
        puts "⚠️  Warning: No caching is occurring!"
      end

      puts ""
    end

    def check_solid_cache_stats
      return unless solid_cache_available?

      puts "📊 SOLID CACHE STATISTICS"
      puts "-" * 40

      stats = solid_cache_stats

      puts "Total entries:     #{format_number(stats[:entry_count])}"
      puts "Total size:        #{format_bytes(stats[:total_bytes])}"
      puts "Max configured:    #{format_bytes(max_cache_size)}"
      puts "Usage:             #{stats[:usage_percent]}%"
      puts "Average entry:     #{format_bytes(stats[:avg_entry_size])}"

      if stats[:oldest_entry]
        puts "Oldest entry:      #{stats[:oldest_entry].strftime('%Y-%m-%d %H:%M:%S')} (#{time_ago_in_words(stats[:oldest_entry])} ago)"
      end

      if stats[:newest_entry]
        puts "Newest entry:      #{stats[:newest_entry].strftime('%Y-%m-%d %H:%M:%S')} (#{time_ago_in_words(stats[:newest_entry])} ago)"
      end

      # Size distribution (only show if there are entries)
      if stats[:entry_count].positive?
        puts "\nSize distribution:"
        distribution = cache_size_distribution
        distribution.each do |range, count|
          bar = "█" * [ (count.to_f / stats[:entry_count] * 30).round, 1 ].max
          pct = (count.to_f / stats[:entry_count] * 100).round(1)
          puts "  #{range.ljust(12)} #{bar} #{count} (#{pct}%)"
        end
      else
        puts "\n⚠️  Cache is empty - no entries to analyze"
      end

      puts ""
    end

    def check_cache_connectivity
      puts "🔌 CACHE CONNECTIVITY TEST"
      puts "-" * 40

      tests = []

      # Write test
      test_key = "diag_#{SecureRandom.hex(8)}"
      test_value = { timestamp: Time.current.to_s, random: SecureRandom.hex(16) }

      begin
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Rails.cache.write(test_key, test_value, expires_in: 5.minutes)
        write_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
        tests << { name: "Write", status: "✅", time: "#{write_time.round(2)}ms" }
      rescue StandardError => e
        tests << { name: "Write", status: "❌", time: e.message }
      end

      # Read test
      begin
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = Rails.cache.read(test_key)
        read_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000

        tests << if result == test_value
                   { name: "Read", status: "✅", time: "#{read_time.round(2)}ms" }
        else
                   { name: "Read", status: "⚠️", time: "Value mismatch" }
        end
      rescue StandardError => e
        tests << { name: "Read", status: "❌", time: e.message }
      end

      # Exist test
      begin
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        exists = Rails.cache.exist?(test_key)
        exist_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
        tests << { name: "Exist", status: exists ? "✅" : "⚠️", time: "#{exist_time.round(2)}ms" }
      rescue StandardError => e
        tests << { name: "Exist", status: "❌", time: e.message }
      end

      # Delete test
      begin
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Rails.cache.delete(test_key)
        delete_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
        tests << { name: "Delete", status: "✅", time: "#{delete_time.round(2)}ms" }
      rescue StandardError => e
        tests << { name: "Delete", status: "❌", time: e.message }
      end

      # Increment test
      begin
        counter_key = "diag_counter_#{SecureRandom.hex(4)}"
        Rails.cache.write(counter_key, 0, expires_in: 1.minute)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        new_val = Rails.cache.increment(counter_key)
        incr_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
        Rails.cache.delete(counter_key)
        tests << { name: "Increment", status: new_val == 1 ? "✅" : "⚠️", time: "#{incr_time.round(2)}ms" }
      rescue StandardError
        tests << { name: "Increment", status: "⚠️", time: "Not supported" }
      end

      tests.each do |t|
        puts "#{t[:status]} #{t[:name].ljust(12)} #{t[:time]}"
      end

      puts ""
    end

    def benchmark_operations
      puts "⏱️  PERFORMANCE BENCHMARKS"
      puts "-" * 40

      iterations = 50

      # Simple value
      simple_times = []
      iterations.times do
        key = "bench_simple_#{SecureRandom.hex(4)}"
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Rails.cache.write(key, "hello", expires_in: 1.minute)
        Rails.cache.read(key)
        Rails.cache.delete(key)
        simple_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      # Complex value (simulating typical ActiveRecord cache)
      complex_data = {
        id: 123,
        name: "Test Object",
        attributes: { a: 1, b: 2, c: 3 },
        nested: [ { x: 1 }, { x: 2 }, { x: 3 } ],
        timestamp: Time.current,
        description: "A" * 500
      }

      complex_times = []
      iterations.times do
        key = "bench_complex_#{SecureRandom.hex(4)}"
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Rails.cache.write(key, complex_data, expires_in: 1.minute)
        Rails.cache.read(key)
        Rails.cache.delete(key)
        complex_times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      puts "Simple value (write + read + delete, #{iterations} iterations):"
      puts "  Min: #{simple_times.min.round(2)}ms"
      puts "  Max: #{simple_times.max.round(2)}ms"
      puts "  Avg: #{(simple_times.sum / simple_times.size).round(2)}ms"
      puts "  P95: #{percentile(simple_times, 95).round(2)}ms"

      puts "\nComplex value (~1KB, write + read + delete, #{iterations} iterations):"
      puts "  Min: #{complex_times.min.round(2)}ms"
      puts "  Max: #{complex_times.max.round(2)}ms"
      puts "  Avg: #{(complex_times.sum / complex_times.size).round(2)}ms"
      puts "  P95: #{percentile(complex_times, 95).round(2)}ms"

      # Throughput estimate
      ops_per_sec = (1000.0 / (simple_times.sum / simple_times.size) * 3).round
      puts "\nEstimated throughput: ~#{format_number(ops_per_sec)} ops/sec (simple)"

      puts ""
    end

    def analyze_cache_keys
      return unless solid_cache_available?

      puts "🔑 CACHE KEY ANALYSIS"
      puts "-" * 40

      # Get sample of cache keys
      entries = SolidCache::Entry.limit(1000).pluck(:key, :byte_size)

      if entries.empty?
        puts "No cache entries found."
        puts ""
        return
      end

      # Decode keys and analyze patterns
      key_patterns = Hash.new { |h, k| h[k] = { count: 0, bytes: 0 } }

      entries.each do |key_binary, byte_size|
        key = key_binary.to_s.dup.force_encoding("UTF-8")

        # Extract key pattern (first segment or prefix)
        pattern = extract_key_pattern(key)
        key_patterns[pattern][:count] += 1
        key_patterns[pattern][:bytes] += byte_size
      end

      # Sort by count
      sorted = key_patterns.sort_by { |_, v| -v[:count] }.first(15)

      puts "Top key patterns (from sample of #{entries.size}):"
      puts ""
      puts "#{'Pattern'.ljust(40)} #{'Count'.rjust(8)} #{'Size'.rjust(12)}"
      puts "-" * 62

      sorted.each do |pattern, stats|
        puts "#{pattern.truncate(40).ljust(40)} #{stats[:count].to_s.rjust(8)} #{format_bytes(stats[:bytes]).rjust(12)}"
      end

      puts ""
    end

    def check_fragment_cache_usage
      puts "🧩 FRAGMENT CACHE ANALYSIS"
      puts "-" * 40

      # Find fragment cache calls in views
      view_files = Dir.glob(Rails.root.join("app/views/**/*.erb"))
      fragment_caches = []

      view_files.each do |file|
        content = File.read(file)
        # Match cache blocks: <% cache ... do %>
        content.scan(/<%.*?cache\s+(\[.*?\]|[^,\s]+)/).each do |match|
          fragment_caches << {
            file: file.sub("#{Rails.root}/", ""),
            key: match[0]
          }
        end
      end

      if fragment_caches.empty?
        puts "No fragment caches found in views."
        puts ""
        puts "💡 Opportunity: Consider adding fragment caching to expensive view partials."
        puts "   Example: <% cache [model, 'partial_name'] do %>"
      else
        puts "Found #{fragment_caches.size} fragment cache(s) in views:\n\n"

        fragment_caches.group_by { |fc| fc[:file] }.each do |file, caches|
          puts "📄 #{file}"
          caches.each do |cache|
            puts "   └─ cache #{cache[:key]}"
          end
        end
      end

      puts ""
    end

    def provide_recommendations
      puts "💡 RECOMMENDATIONS"
      puts "-" * 40

      recommendations = []

      if solid_cache_available?
        stats = solid_cache_stats

        # Check usage level
        if stats[:usage_percent] > 90
          recommendations << {
            priority: "HIGH",
            issue: "Cache is #{stats[:usage_percent]}% full",
            action: "Consider increasing max_size in config/cache.yml or reviewing expiration policies"
          }
        elsif stats[:usage_percent] < 10
          recommendations << {
            priority: "INFO",
            issue: "Cache usage is very low (#{stats[:usage_percent]}%)",
            action: "This may indicate cache is underutilized or recently cleared. Consider adding more caching."
          }
        end

        # Check for old entries (might indicate missing expiration)
        if stats[:oldest_entry] && stats[:oldest_entry] < 30.days.ago
          recommendations << {
            priority: "MEDIUM",
            issue: "Oldest cache entry is over 30 days old",
            action: "Consider setting max_age in config/cache.yml to enforce retention policies"
          }
        end

        # Check entry count vs size ratio
        if stats[:entry_count].positive? && stats[:avg_entry_size] > 100.kilobytes
          recommendations << {
            priority: "MEDIUM",
            issue: "Average cache entry is large (#{format_bytes(stats[:avg_entry_size])})",
            action: "Large entries can slow down serialization. Consider caching smaller objects."
          }
        end
      end

      # Check for common caching opportunities
      fragment_count = Dir.glob(Rails.root.join("app/views/**/*.erb")).count do |f|
        File.read(f).include?("cache ")
      end

      total_views = Dir.glob(Rails.root.join("app/views/**/*.erb")).count

      if fragment_count.to_f / total_views < 0.05
        recommendations << {
          priority: "INFO",
          issue: "Fragment caching is used in only #{fragment_count}/#{total_views} view files",
          action: "Consider adding fragment caching to expensive or frequently-rendered partials"
        }
      end

      # Check for Russian doll caching opportunities
      partials = Dir.glob(Rails.root.join("app/views/**/_*.erb")).count
      cached_partials = Dir.glob(Rails.root.join("app/views/**/_*.erb")).count { |f| File.read(f).include?("cache ") }

      if partials > 10 && cached_partials.to_f / partials < 0.1
        recommendations << {
          priority: "INFO",
          issue: "#{partials} partials found, only #{cached_partials} use fragment caching",
          action: "Consider Russian doll caching for nested partials with proper cache keys"
        }
      end

      if recommendations.empty?
        puts "✅ No immediate issues detected. Cache appears healthy!"
      else
        recommendations.each do |rec|
          icon = case rec[:priority]
          when "HIGH" then "🔴"
          when "MEDIUM" then "🟡"
          else "🔵"
          end

          puts "#{icon} [#{rec[:priority]}] #{rec[:issue]}"
          puts "   → #{rec[:action]}"
          puts ""
        end
      end
    end

    # Helper methods

    def solid_cache_available?
      defined?(SolidCache::Entry) && SolidCache::Entry.table_exists?
    rescue StandardError
      false
    end

    def solid_cache_stats
      return {} unless solid_cache_available?

      entry_count = SolidCache::Entry.count
      total_bytes = SolidCache::Entry.sum(:byte_size)
      oldest = SolidCache::Entry.minimum(:created_at)
      newest = SolidCache::Entry.maximum(:created_at)
      max_size = max_cache_size

      {
        entry_count: entry_count,
        total_bytes: total_bytes,
        avg_entry_size: entry_count.positive? ? total_bytes / entry_count : 0,
        oldest_entry: oldest,
        newest_entry: newest,
        usage_percent: max_size.positive? ? (total_bytes.to_f / max_size * 100).round(1) : 0
      }
    end

    def max_cache_size
      # Parse from config/cache.yml
      256.megabytes # Default from your config
    end

    def cache_size_distribution
      return {} unless solid_cache_available?

      ranges = {
        "< 1 KB" => 0,
        "1-10 KB" => 0,
        "10-100 KB" => 0,
        "100KB-1MB" => 0,
        "> 1 MB" => 0
      }

      SolidCache::Entry.pluck(:byte_size).each do |size|
        case size
        when 0...1024 then ranges["< 1 KB"] += 1
        when 1024...10_240 then ranges["1-10 KB"] += 1
        when 10_240...102_400 then ranges["10-100 KB"] += 1
        when 102_400...1_048_576 then ranges["100KB-1MB"] += 1
        else ranges["> 1 MB"] += 1
        end
      end

      ranges
    end

    def extract_key_pattern(key)
      # Remove namespace prefix if present
      key = key.sub(/^[^:]+:/, "")

      # Extract meaningful pattern
      if key.include?("/")
        # View cache key like "views/products/show/..."
        parts = key.split("/")
        parts[0..[ 2, parts.length - 1 ].min].join("/")
      elsif key.include?(":")
        # Namespaced key
        key.split(":").first(2).join(":")
      else
        # Simple key - take first segment
        key.split("_").first(2).join("_")
      end
    end

    def benchmark_operation(name, iterations: 100)
      times = []

      iterations.times do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
        times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
      end

      result = {
        min: times.min,
        max: times.max,
        avg: times.sum / times.size,
        p95: percentile(times, 95)
      }

      puts "#{name.ljust(25)} avg: #{result[:avg].round(2)}ms  p95: #{result[:p95].round(2)}ms"
      result
    end

    def percentile(array, p)
      sorted = array.sort
      index = (p.to_f / 100 * sorted.size).ceil - 1
      sorted[[ index, 0 ].max]
    end

    def format_bytes(bytes)
      return "0 B" if bytes.nil? || bytes.zero?

      units = %w[B KB MB GB TB]
      exp = (Math.log(bytes) / Math.log(1024)).to_i
      exp = [ exp, units.size - 1 ].min

      format("%.1f %s", bytes.to_f / 1024**exp, units[exp])
    end

    def format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    def time_ago_in_words(time)
      seconds = (Time.current - time).to_i
      case seconds
      when 0..59 then "#{seconds} seconds"
      when 60..3599 then "#{seconds / 60} minutes"
      when 3600..86_399 then "#{seconds / 3600} hours"
      else "#{seconds / 86_400} days"
      end
    end
  end
end
