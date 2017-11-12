# Load Configuration
require_relative 'configuration'
require_relative 'expense_helpers'
require_relative 'expense_viewer'
require 'csv'
require 'pry'
require 'json'
require 'date'

# Define the hashes that will be used to

# Create regex rules based on the configuration groups
group_matchers = {}
# group_matchers = {
#     group_name => {
#         regex => Regexp.union([/abc/,/def/]),
#         additional_rules => [
#             {
#                 regex => /abc/,
#                 rules => [
#                     {
#                         type => compare,
#                         field => Amount,
#                         operator => <,
#                         value => ...
#                     }
#                 ],
#                 ...
#             }
#         ]
#     }
# }
group_transactions().each do |group|
    regexes = []
    additional_rules = []
    group["matchers"].each do |rules|
        additional = nil
        rules.split("(").each_with_index do |rule,i|
            if i == 0; regexes.push(Regexp.new("#{rule.gsub("%",".*?")}","i"))
            else;
                additional = {"regex" => regexes[-1]} if additional.nil?
                if match = /amount([<>])(\d+)/i.match(rule); r = {"type"=>"compare","field" => "Amount","operator" => match.captures[0],"value"=>match.captures[1].to_i} end
                additional.key?("rules") && defined?(r) != nil ? additional["rules"].push(r) : additional["rules"] = [r]
            end
        end
        additional_rules.push(additional) if !additional.nil?
    end
    group_matchers[group["name"]] = {"regex" => Regexp.new("\\A#{Regexp.union(regexes)}\\z","i"), "additional_rules" => additional_rules}
end

# Initialize the data hashes (one for each specific account that will be tracked and then one for everything else)
transactions = {}
separated_accounts = accounts_to_separate()
separated_accounts.push("General").each do |account|
    transactions[account] = {
        "months" => {},
        "names"  => {},
        "groups" => {},
        "recurring" => []
    }
end

# Load the csv file containing the transactions and iterate through it
CSV.foreach("transactions.csv", headers: true) do |t|
    month = get_month(t["Date"])
    account = separated_accounts.include?(t["Account Name"]) ? t["Account Name"] : "General"

    # If the name doesn't match, classify the transaction as income or an expense
    type = t["Transaction Type"] == "credit" ? "income" : "expenses"
    transactions[account]["months"][month] = {"income" => {}, "expenses" => {}} if !transactions[account]["months"].key?(month)

    match = false
    group_matchers.each do |name,group|
        # If the name matches a group identifier
        if group["regex"].match(t["Description"])
            # If it matches one of the group regexes, run it through any additonal rules to make sure it matches those too
            match = true
            group["additional_rules"].each do |additional|
                if additional["regex"].match(t["Description"])
                    additional["rules"].each do |rule|
                        if rule["type"] == "compare"; match = rule["operator"] == "<" ? t[rule["field"]].to_f < rule["value"] : t[rule["field"]].to_f > rule["value"] end
                        break if !match
                    end
                end
            end
            # If it matches additional rules, load it into a month-sorted group hash and continue to the next transaction
            if match
                # Add the group name to "groups" if this is the first group match
                transactions[account]["groups"][name] = {} if !transactions[account]["groups"].key?(name)
                # Add the transaction to the month - create the month first if the key doesn't exist
                transactions[account]["groups"][name].key?(month) ? transactions[account]["groups"][name][month].push(t) : transactions[account]["groups"][name][month] = [t]
                next
            end
        end
    end

    # If a transactions is not a group transactions
    if !match
        # Load the transaction into a month-sorted hash (stored in a hash in the form of amount => transaction)
        transactions[account]["months"][month][type][t["Amount"]] = transactions[account]["months"][month][type][t["Amount"]].nil? ? [t] : transactions[account]["months"][month][type][t["Amount"]] + [t]
        # Load the transaction into a name-sorted hash
        transactions[account]["names"].key?(t["Description"]) ? transactions[account]["names"][t["Description"]].push(t) : transactions[account]["names"][t["Description"]] = [t]
    end
end

separated_accounts.each do |account|
    # For each group collections that was created
    transactions[account]["groups"].each do |name,months|
        # Combine the group into a single transaction for each month
        months.each do |m,t|
            group_t = {"Description" => name, "Date" => m.gsub("/","/15/20"), "Transactions" => t, "Amount" => t.reduce(0) {|s,r| s += r["Amount"].to_f }}
            # Load into a month-sorted hash
            type = t[0]["Transaction Type"] == "credit" ? "income" : "expenses"
            transactions[account]["months"][m][type][group_t["Amount"]] = transactions[account]["months"][m][type][group_t["Amount"]].nil? ? [group_t] : transactions[account]["months"][m][type][group_t["Amount"]] + [group_t]
            # Load into a group-sorted hash
            transactions[account]["names"].key?(name) ? transactions[account]["names"][name].push(group_t) : transactions[account]["names"][name] = [group_t]
        end
    end

    # Remove any credit card payments (or any other transactions with a mirrored income/expense)
    transactions[account]["months"].keys.each do |month|
        account_month = transactions[account]["months"][month]
        # Look for intersections for each months income/expenses amount
        cc_payment_amounts = account_month["income"].keys & account_month["expenses"].keys
        # Remove these values from income if both ["income"][amount] and ["expenses"][amount] both only have 1 instance
        cc_payment_amounts.each do |amount|
            # Mark for removal
            mark_for_removal = {"income" => [], "expenses" => []}
            if account_month["income"][amount].size == 1 && account_month["expenses"][amount].size == 1
                if account_month["income"][amount][0]["Account Name"] != account_month["expenses"][amount][0]["Account Name"]
                    mark_for_removal["income"].push(account_month["income"][amount][0])
                    mark_for_removal["expenses"].push(account_month["expenses"][amount][0])
                end
            else
                # For each income transaction, iterate through and try to match any income transaction
                # with an equal expense from a different account
                account_month["income"][amount].each do |income|
                    account_month["expenses"][amount].each do |expense|
                        if income["Account Name"] != expense["Account Name"]
                            mark_for_removal["income"].push(income)
                            mark_for_removal["expenses"].push(expense)
                        end
                    end
                end
            end
            # Remove the transactions marked for removal
            mark_for_removal.each do |type,t_list|
                t_list.each do |t|
                    # Remove from the month list
                    account_month[type][amount].delete(t)
                    account_month[type].delete(amount) if account_month[type][amount].empty?
                    # Remove from the name list
                    transactions[account]["names"][t["Description"]].delete(t)
                    transactions[account]["names"].delete(t["Description"]) if transactions[account]["names"][t["Description"]].empty?
                end
            end
        end
    end

    # Find recurring events based on the name-sorted hash
    transactions[account]["names"].each do |name,trans|
        next unless trans.size > 1 # If a name only has 1 transaction, it can't be a recurring event

        # Create distinct distribution categories based on similar transaction amounts
        distribution = {}
        trans.each do |t|
            amount = t["Amount"].to_f
            match = distribution.keys.detect { |range| amount > range[0] && amount < range[1] }
            if match
                distribution[match].push(t)
            else
                # If no distribution keys are within $5 or 5% of the current instance, create a new distribution key
                d_spread = [10*0.05,5].max
                distribution[[amount-d_spread,amount+d_spread]] = [t]
            end
        end

        # Using the distribution, check for recurring events
        distribution.each do |range,dt|
            # If there are more than 1 distribution transations, check for recurring events
            next unless dt.size > 1

            recurring_event = detect_recurring_event(dt)
            if recurring_event
                recurring_event["name"] = name
                transactions[account]["recurring"].push(recurring_event)
            end
        end
    end
end

# use_data(transactions)
expense_viewer = ExpenseViewer.new(transactions)
expense_viewer.view
# expense_viewer.previous_months_report("General",3)

# Use the transaction data

    # List all the recurring events that were found

        # Optionally list all the transactions for each recurring event

    # List the net income/expenses for each month

        # Optionally list all the expenses/income sorted from big -> small in each month

    # List the pace of the current month

    # List the expected expenses in the next n months

    # Take at when big purchases happen? (maybe > $400?)