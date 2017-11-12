# Given a date, generates the month that that date is in, in the form of MM/YY
def get_month(date)
    d = Date.strptime(date, "%m/%d/%Y")
    return "#{d.month}/#{d.year-2000}"
end

def float_to_dollar(float)
    dollar = float.to_f.to_s
    if /\d+\.\d{2,}/.match(dollar)
        dollar = dollar[0..dollar.index(".")+2]
    else
        dollar += "0"
    end
    return "$#{dollar}"
end

def detect_recurring_event(transaction_list)
    # Create a hash of ruby dates and transactions amounts
    date_amount_hash = {}
    transaction_list.each { |t| date_amount_hash[Date.strptime(t["Date"],"%m/%d/%Y")] = t["Amount"].to_f }

    # Sort the array and grab the first 6 values to find the average date spread (dropping
    # the outliers)
    dates = date_amount_hash.keys.sort.reverse
    first_six = dates.slice(0,6)

    return nil if first_six.size <= 1

    spreads = first_six.each_cons(2).map { |a,b| (a-b).to_i}.sort
    while spreads.size > 3
        spreads[1] - spreads[0] > spreads[-1] - spreads[-2] ? spreads.shift : spreads.pop
    end
    average_spread = (spreads.inject(0,:+)/spreads.size).to_i

    return nil if average_spread > 375 || average_spread < 7

    # Count the amount of date spread outliers that don't fit the average spread
    prev_spread = 0 # A variable used to help the case where a date in-between 2 normal spreads doesn't cause 2 bad spread outliers
    outliers = dates.each_cons(2).inject(0) do |a,b|
        spread = (b[0]-b[1]).to_i + prev_spread
        if spread < average_spread-8; prev_spread = spread; a+1;
        elsif spread > average_spread+8; prev_spread = 0; a+1;
        else; a; end
    end
    
    if outliers <= ((dates.size - 4)/3 + 1)
        current = dates.first > Date.today-(average_spread+10)
        if dates.size > 2 || (dates.size == 2 && current)
            recurring = {"start_date" => dates.last, "end_date" => dates.first, "frequency" => average_spread, 
                "transactions" => transaction_list, "current?" => current}
            recurring["income?"] = transaction_list[0]["Transaction Type"].to_s.downcase == "credit"
            recurring["monthly?"] = average_spread > 26 && average_spread < 34
            recurring["amount"] = dates.size == 2 ? date_amount_hash[dates[0]] : date_amount_hash.values_at(*dates.slice(0,3)).sort[1]

            return recurring
        end
    end
    return nil
end

###############################################################################
#                            NAVIGATION HELPERS                               #
###############################################################################

def use_data(transaction_data)
    binding.pry
    navigate(transaction_data,[],{})
end

def navigate(transactions,breadcrumb,stored_data)
    breadcrumb_copy = breadcrumb.clone
    if breadcrumb.empty?
        stored_data[:pick_an_account] = pick_an_account(transactions.keys)
        breadcrumb.push(:pick_an_account)
    elsif breadcrumb.size == 1
        stored_data[:pick_an_action] = pick_an_action(stored_data[:pick_an_account])
        breadcrumb.push(:pick_an_action)
    elsif breadcrumb.size == 2 && stored_data[:pick_an_action] == "1"
        stored_data[:pick_recurring_action] = pick_recurring_action(stored_data[:pick_an_account])
        breadcrumb.push(:pick_an_action)
    end

    # Check to see if the last call was a 'back' request
    if stored_data[breadcrumb[-1]] == false
        breadcrumb.pop(2)
        navigate(transactions,breadcrumb,stored_data)
    elsif breadcrumb.size == breadcrumb_copy.size
        puts "An unexpected navigation error occurred"
    else
        navigate(transactions,breadcrumb,stored_data)
    end
end

def navigation_input(*input_rules)
    print "(q=quit,b=back) --> "
    input = gets.strip.downcase
    exit if input == "q" || input == "quit" || input == "exit"
    return false if input == "b" || input == "back"
    input_rules.each do |rule|
        if rule.is_a?(Regexp)
            return navigation_input(*input_rules) if !rule.match(input)
        elsif rule.is_a?(Array)
            return navigation_input(*input_rules) if !rule.include?(input)
        end
    end
    return input
end

def pick_an_account(separated_accounts)
    puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    puts "Pick an account to view"
    separated_accounts.each_with_index do |name,i|
        puts "[#{i+1}] #{name}"
    end
    input = navigation_input(("1".."#{separated_accounts.size}").to_a)
    return input == false ? false : separated_accounts[input.to_i-1]
end

def pick_an_action(account_name)
    puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    puts "Pick a data view for this account (#{account_name})"
    puts "[1] Recurring Events"
    puts "[2] Past Month(s) Report"
    puts "[3] Current Month Report"
    puts "[4] Future Month(s) Report"
    input = navigation_input(("1".."4").to_a)
    return input
end

def pick_recurring_action(account_name)
    puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    puts "View Recurring Events (#{account_name})"
    puts "[1] Current Events"
    puts "[2] Legacy Events"
    puts "[3] More Options"
    input = navigation_input(("1".."3").to_a)
    return input
end

def past_months_report(amount_of_months)
    puts transactions.inspect
end
