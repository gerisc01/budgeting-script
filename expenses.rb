require 'csv'
require 'date'

# Options
list_recurring_payments = true               # including old and new payments
list_recurring_payment_transactions = false   # list all the transactions found for each recurring payment
list_current_month = false
list_next_month = false

# Define group transactions
group_transactions = [
    {
        "name" => "Work Parking",
        "matchers" => [
            "6th St Parking Ramp",
            "Keefe Co Parking"
        ]
    },
    {
        "name" => "Work Lunch",
        "matchers" => [
            "erbert%gerberts%",
            "%asian express%",
            "%nectary%",
            "%zantigo%",
            "potbelly%",
            "skyway grill%",
            "leeann chin%(amount<15)",
            "subway%(amount<12)",
            "sprout%",
            "chipotle%(amount<12)",
            "bulldog%(amount<25)"
        ]
    },
    {
        "name" => "Car Payment",
        "matchers" => ["check%(amount>255)(amount<265)"]
    }
]

# Finds the nearest month start (most useful for when joint payments are made in the last few days of the previous month
# when they are actually meant for the next month (aka. Transfer for Feb made on Jan 31)). Assumes the input date is in
# the form of MM/dd/YYYY and output will be in the form of MM/YY
def nearest_month(date)
    d = Date.strptime(date, "%m/%d/%Y")
    month = d.month
    year = d.year-2000
    
    month += 1 if d.day > 15
    if month > 12
        month = month % 12
        year += 1
    end
    return "#{month}/#{year}"
end

# Given a date, generates the month that that date is in, in the form of MM/YY
def get_month(date)
    d = Date.strptime(date, "%m/%d/%Y")
    return "#{d.month}/#{d.year-2000}"
end

def remove_date_spread_outliers(dates)
    date_spreads = []
    return [0] if dates.size <= 1

    prev_date = nil
    dates.sort.reverse.each do |current_date|
        date_spreads.push((prev_date - current_date).to_i) unless prev_date.nil?
        prev_date = current_date
    end
    date_spreads.sort!

    while date_spreads.size > 4
        if (date_spreads[1] - date_spreads[0]) > (date_spreads[-1] - date_spreads[-2])
            date_spreads = date_spreads.slice(1,date_spreads.size)
        else
            date_spreads = date_spreads.slice(0,date_spreads.size-2)
        end
    end
    return date_spreads
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

# If an input is within $5 or 5% of the distribution key
def within_distribution(distribution_key,input)
    five_percent = distribution_key * 0.05
    separation = five_percent < 5 ? 5.0 : five_percent

    return true if input > distribution_key - separation && input < distribution_key + separation
    return false
end

def get_recurring_from_distribution(distribution,name)
    # matching_distribution = {"start_date" : ..., "end_date" : ..., "amount" : ..., "current" : true/false,"transactions" : ...}
    recurring_transactions = []
    distribution.each do |k,v|
        dateAmountHash = {}
        if v.size > 1
            # Start by creating a hash of the dates and amounts
            v.each { |inst| dateAmountHash[Date.strptime(inst["Date"],"%m/%d/%Y")] = inst["Amount"].to_f }

            # Grab the first 6 values from the array and find the average spread date dropping
            # the first and last outlier date spreads
            dates = dateAmountHash.keys.sort.reverse
            firstSix = dateAmountHash.keys.slice(0,6)

            firstSix = remove_date_spread_outliers(firstSix)
            average_spread = 0
            firstSix.each { |d| average_spread += d }
            average_spread /= firstSix.size
            average_spread = average_spread.to_i

            # Don't look for anything that happens more than a year or anything under
            # 2 weeks (should be caught in an aggregate over pay-period if it is under)
            if average_spread > 14 && average_spread < 380
                outliers = 0
                prev_date = nil
                dates.each_with_index do |current_date,index|
                    date_spread = (prev_date - current_date).to_i unless prev_date.nil?
                    prev_date = current_date

                    outliers += 1 if !date_spread.nil? && (date_spread < average_spread-8 || date_spread > average_spread+8)
                end

                if outliers <= ((dates.size - 4)/3 + 1)
                    end_date = dates.first
                    # If a transaction was made in the previous average_spread+10 days timeframe
                    current = end_date > Date.today-(average_spread+10)
                    recurring = {}
                    if dateAmountHash.size > 2 || (dateAmountHash.size == 2 && current)
                        recurring["name"] = name
                        recurring["amount"] = k
                        recurring["start_date"] = dates.last
                        recurring["end_date"] = end_date
                        recurring["frequency"] = average_spread
                        recurring["isCurrent"] = current
                        recurring["isMonthly"] = (average_spread > 26 && average_spread < 34)
                        recurring["isIncome"] = v[0]["Transaction Type"].to_s.downcase == "credit"
                        recurring["transactions"] = v
                    end
                    recurring_transactions.push(recurring) if !recurring.empty?
                end
            end
        end
    end
    return recurring_transactions
end

data = {}
# Create a key for each month starting with the first month specified with the month variable below
month = "6/13"
next_month = "#{Date.today.month+1}/#{Date.today.year-2000}"
while month != next_month
    data[month] = {}
    data[month]["net"] = 0
    data[month]["in"] = []
    data[month]["out"] = []

    month = month.split("/")[0] != "12" ? "#{month.split("/")[0].to_i+1}/#{month.split("/")[1]}" : "1/#{month.split("/")[1].to_i+1}"
end

# Sort all transactions by name to make it easier to find recurring expenses
separated_names = {}
separated_months = {}
groups = {}

# Create regex rules from define group transactions property input
group_rules = []
group_transactions.each do |group|
    name = group["name"]
    groups[name] = []
    group["matchers"].each do |rules|
        matchers = []
        split_rules = rules.split("(")
        matchers.push({"type" => "regex", "field" => "Description", "value" => /\A#{split_rules[0].gsub("%",".*?")}\z/i})
        split_rules.slice(1,split_rules.size).each do |other_patterns|
            if other_patterns.include?("amount")
                match_data = /amount([<>])(\d+)/i.match(other_patterns)
                matchers.push({"type" => "compare", "field" => "Amount", "operator" => match_data[1], "value" => match_data[2].to_i})
            end
        end
        group_rules.push({"name" => name, "matchers" => matchers})
    end
end

# Convert CSV file into ruby dictionary objects and sort expenses by name
CSV.foreach("transactions.csv", headers: true) do |t|
    month = get_month(t["Date"])
    if t["Account Name"] == "Joint Account"
        if t["Transaction Type"] == "debit"
            month = nearest_month(t["Date"]) if t["Description"].downcase.include? "xcel"
            data[month]["net"] -= t["Amount"].to_f
            data[month]["out"].push t
        end

        if t["Transaction Type"] == "credit"
            data[nearest_month(t["Date"])]["net"] += t["Amount"].to_f
            data[nearest_month(t["Date"])]["in"].push t
        end
    else
        if t["Transaction Type"] != "Credit Card Payment"
            # Check to see if is a group transaction
            is_group_transaction = false
            group_rules.each do |rule|
                failed_match = false
                rule["matchers"].each do |matcher|
                    if matcher["type"] == "regex"
                        failed_match = true if matcher["value"].match(t[matcher["field"]]).nil?
                    elsif matcher["type"] == "compare"
                        if matcher["operator"] == "<"
                            failed_match = true if matcher["value"] < t[matcher["field"]].to_f
                        elsif matcher["operator"] == ">"
                            failed_match = true if matcher["value"] > t[matcher["field"]].to_f
                        end
                    end
                    break if failed_match
                end
                if !failed_match
                    groups[rule["name"]].push(t)
                    is_group_transaction = true
                    break
                end
            end

            if !is_group_transaction
                # Push the info into separated months
                separated_months[month] = [] if !separated_months.keys.include?(month)
                separated_months[month].push(t)

                # Push the info into separated names
                separated_names[t["Description"]] = [] if !separated_names.keys.include?(t["Description"])
                separated_names[t["Description"]].push(t)
            end
        end
    end
end

# Strip out the credit card payments by looking for an income source and payment
# that have the same amount in the same month
    # Might be easier if split into different income and array hashes at this point?

# For each group, combine each month's worth of transactions into a single month
groups.each do |name,transactions|
    months = {}
    transactions.each do |t|
        month = get_month(t["Date"])
        if !months.keys.include?(month)
            date = month.split("/").insert(1,"28")
            date[2] = date[2].to_i
            date[2] += 2000
            months[month] = {"Description" => name, "Amount" => 0, "Date" => date.join("/"), "groupSet" => true, "transactions" => []}
        end
        # Increment the amount
        months[month]["Amount"] += t["Amount"].to_f
        # Add transaction to list
        months[month]["transactions"].push(t)
    end

    months.each do |month,value|
        # Push the info into separated months
        separated_months[month] = [] if !separated_months.keys.include?(month)
        separated_months[month].push(value)

        # Push the info into separated names
        separated_names[name] = [] if !separated_names.keys.include?(name)
        separated_names[name].push(value)
    end
end


# Iterate through the transactions and find any recurring transactions
recurring_transactions = []
separated_names.each do |name,instances|
    if instances.size != 1
        distrib = {}
        instances.each do |inst|
            # Create a transaction distribution with all transactions within $5 or 5% of each other
            dollars = inst["Amount"].to_f
            within_distribution = false
            distrib.keys.each do |amount|
                within_distribution = within_distribution(amount,dollars)
                if within_distribution
                    distrib[amount].push(inst)
                    break
                end
            end
            distrib[dollars] = [inst] if !within_distribution
        end

        get_recurring_from_distribution(distrib,name).each { |r| recurring_transactions.push(r) }
    end
end

# List monthly payments
if list_recurring_payments
    current_recurring = {"Monthly" => []}
    legacy_recurring = {"Monthly" => []}

    recurring_transactions.each { |recurring| recurring["isCurrent"] ? current_recurring["Monthly"].push(recurring) : legacy_recurring["Monthly"].push(recurring) }

    puts "Legacy Monthly Payments"
    legacy_recurring["Monthly"].each do |recurring|
        puts "  Name: #{recurring["name"]} - #{float_to_dollar(recurring["amount"])} (every #{recurring["frequency"]} days)"
        puts "      #{recurring["start_date"]} -> #{recurring["end_date"]}"
        if list_recurring_payment_transactions
            prev_date = nil
            recurring["transactions"].each do |transaction|
                current_date = Date.strptime(transaction["Date"],"%m/%d/%Y")
                date_spread = prev_date.nil? ? "" : (prev_date - current_date).to_i
                puts "          #{transaction["Date"]}: #{transaction["Amount"]} -- #{date_spread}"
                prev_date = current_date
            end
        end
    end

    puts "\n"

    puts "Recurring Monthly Payments"
    monthly_total = 0
    current_recurring["Monthly"].each do |recurring|
        monthly_total += recurring["amount"]
        puts "  Name: #{recurring["name"]} - #{float_to_dollar(recurring["amount"])} (every #{recurring["frequency"]} days)"
        if list_recurring_payment_transactions
            prev_date = nil
            recurring["transactions"].each do |transaction|
                current_date = Date.strptime(transaction["Date"],"%m/%d/%Y")
                date_spread = prev_date.nil? ? "" : (prev_date - current_date).to_i
                puts "          #{transaction["Date"]}: #{transaction["Amount"]} -- #{date_spread}"
                prev_date = current_date
            end
        end
    end
end

if list_next_month
    # Next Month
    puts "~~~~~ May 2017 ~~~~~"
    month = 5
    income = {"items" => [], "net" => 0}
    payments = {"items" => [], "net" => 0}
    recurring_transactions.each do |recurring|
        if recurring["isCurrent"]
            if recurring["isMonthly"] || (!recurring["isMonthly"] && (recurring["end_date"]+recurring["frequency"]).month == month)
                if recurring["isIncome"]
                    income["items"].push(recurring)
                    income["net"] += recurring["amount"]
                else
                    payments["items"].push(recurring)
                    payments["net"] -= recurring["amount"]
                end
            end
        end
    end

    puts "Expected Income: #{float_to_dollar(income["net"])}"
    income["items"].each do |item|
        puts "  #{item["name"]}: #{float_to_dollar(item["amount"])}"
    end
    puts "\n"
    puts "Expected Payments: #{float_to_dollar(payments["net"])}"
    payments["items"].each do |item|
        puts "  #{item["name"]}: #{float_to_dollar(item["amount"])}"
    end
end

# month = 9
# year = 16
# begin
#     income = {"items" => [], "net" => 0}
#     expenses = {"items" => [], "net" => 0}

#     separated_months["#{month}/#{year}"].each do |t|
#         if t["Transaction Type"] == "credit"
#             income["items"].push(t)
#             income["net"] += t["Amount"].to_f
#         else
#             expenses["items"].push(t)
#             expenses["net"] += t["Amount"].to_f
#         end
#     end

#     puts "~~~~~ #{month}/#{year} ~~~~~"
#     puts "Income:    #{float_to_dollar(income["net"])}"
#     income["items"].each do |i|
#         puts "    #{i["Description"]} - #{i["Amount"]}"
#     end
#     puts ""
#     puts "Expenses:  #{float_to_dollar(expenses["net"])}"
#     expenses["items"].sort_by! { |item| item["Amount"].to_f }
#     expenses["items"].reverse.each do |i|
#         puts "    #{i["Description"]} - #{i["Amount"]}"
#     end
#     puts "Month Net: #{float_to_dollar(income["net"]-expenses["net"])}"
#     puts ""
#     month += 1
#     if month > 12
#         month = 1
#         year += 1
#     end
# end until month == 5 && year == 17
