namespace :users do
  desc "Clean up malicious user accounts created by bots"
  task cleanup_malicious: :environment do
    puts "Searching for malicious user accounts..."
    
    # Find users with suspicious email patterns
    malicious_patterns = [
      /[\x00-\x1f\x7f]/,  # Control characters
      /[<>"'`\\;|&$(){}]/,  # Shell injection characters
      /(bin|cat|etc|passwd|wget|curl|bash|sh|exec|eval)/i,  # Command keywords
      /\s=\s/,  # Spaces with equals (like "ybdix =ybdix")
      %r{/bin/},  # Unix paths
      /\\x/  # Hex escape sequences
    ]
    
    malicious_users = User.where.not(email_address: User::GOD_MODE_EMAILS).select do |user|
      malicious_patterns.any? { |pattern| user.email_address.match?(pattern) }
    end
    
    puts "Found #{malicious_users.count} malicious user accounts"
    
    if malicious_users.any?
      puts "\nMalicious accounts to delete:"
      malicious_users.each do |user|
        puts "  - ID: #{user.id}, Email: #{user.email_address}, Created: #{user.created_at}"
      end
      
      print "\nDelete these accounts? (y/N): "
      response = STDIN.gets.chomp.downcase
      
      if response == 'y'
        ActiveRecord::Base.transaction do
          malicious_users.each do |user|
            # Delete associated records first
            user.email_logs.destroy_all
            user.sessions.destroy_all
            user.person&.destroy
            user.destroy
            puts "Deleted user #{user.id}: #{user.email_address}"
          end
        end
        puts "\n✓ Successfully deleted #{malicious_users.count} malicious accounts"
      else
        puts "Cancelled. No accounts were deleted."
      end
    else
      puts "No malicious accounts found."
    end
  end
end
