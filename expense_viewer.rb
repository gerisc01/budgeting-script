class ExpenseViewer

    def initialize(transaction_data)
        @transactions = transaction_data
        @current_month = "#{Date.today.month}/#{Date.today.year.to_s[2..-1]}"
    end

    def view
        navigate(@transactions,"",{})
    end

    def recurring_events(account)
        puts "Legacy Recurring Transactions"
        puts "=============================="
        @transactions[account]["recurring"].select { |rec| !rec["current?"] }.each do |t|
            puts "  Name: #{t["name"]} - #{float_to_dollar(t["amount"])} (every #{t["frequency"]} days)"
            puts "      #{t["start_date"]} -> #{t["end_date"]}"
        end

        puts "Current Recurring Transactions"
        puts "=============================="
        @transactions[account]["recurring"].select { |rec| rec["current?"] }.each do |t|
            puts "  Name: #{t["name"]} - #{float_to_dollar(t["amount"])} (every #{t["frequency"]} days)"
            puts "      #{t["start_date"]} -> #{t["end_date"]}"
        end
    end

    def previous_months_report(account)
        amount_of_months = 3
        date = @current_month
        (0...amount_of_months).each do |i|
            # Default variables
            income = 0
            expenses = 0
            date = previous_month(date)

            month = @transactions[account]["months"][date]

            # Default months to empty if no data is present
            month = {"income" => {}, "expenses" => {}} if month.nil?

            month["income"].each do |k,v|
                v.each do |t|
                    income += k.to_f
                end
            end
            month["expenses"].each do |k,v|
                v.each do |t|
                    expenses += k.to_f
                end
            end
            puts "#{date}"
            puts "  Income:   " + float_to_dollar(income)
            puts "  Expenses: " + float_to_dollar(expenses)
            puts "  ------------------"
            puts "  Net:      " + float_to_dollar(income-expenses)

            puts "\n\nTop Transactions"
            puts "Income: "
            month["income"].sort.reverse_each do |k,v|
                v.each do |t|
                    puts "#{t["Description"]} (#{t["Date"]}): #{t["Amount"]}"
                end
            end
            puts "\nExpenses: "
            month["expenses"].sort_by{|k,v| -k.to_f}.each do |k,v|
                v.each do |t|
                    puts "#{t["Description"]} (#{t["Date"]}): #{t["Amount"]}" if k.to_f > 50.0
                end
            end
        end

        # puts @transactions[account]["names"].keys
    end

    def current_month_report(account)
        puts "Not implemented yet"
    end

    def future_month_report(account)
        next_month = @current_month == 12 ? 1 : @current_month.to_i + 1
        month_transactions = @transactions[account]["recurring"].select { |rec|
            rec["current?"] && (rec["monthly?"] || ((rec["end_date"]+rec["frequency"]).month == next_month))
        }

        income_transactions = month_transactions.select { |t| t["income?"] }
        expense_transactions = month_transactions.select { |t| !t["income?"] }

        income = income_transactions.inject(0){ |sum,t| sum += t["amount"]}
        expenses = expense_transactions.inject(0){ |sum,t| sum += t["amount"]}

        puts "Month: #{@current_month}"
        puts "  Income:   " + float_to_dollar(income)
        puts "  Expenses: " + float_to_dollar(expenses)
        puts "  ------------------"
        puts "  Net:      " + float_to_dollar(income-expenses)

        puts "Expected Income:"
        income_transactions.sort_by{|t| t["amount"]}.each do |t|
            puts "#{t["name"]} - #{t["amount"]}"
        end

        puts "Expected Expenses:"
        expense_transactions.sort_by{|t| -t["amount"]}.each do |t|
            puts "#{t["name"]} - #{t["amount"]}"
        end
    end

    ###############################################################################
    #                             VIEWER HELPERS                                  #
    ###############################################################################

    def previous_month(month)
        month,year = month.split("/")
        new_month = month.to_i-1
        return new_month == 0 ? "12/#{year.to_i-1}" : "#{new_month}/#{year}"
    end

    def navigate(transactions,account,stored_data)
        result = nil
        if (account.to_s.empty?)
            result = pick_an_account(transactions.keys)
            account = result
        else
            result = pick_an_action(account)
            action = result
        end

        # Check to see if the last call was a 'back' request
        if result == false
            navigate(transactions,"",{})
        else
            puts action
            self.send(action,account) if !action.nil?
            navigate(transactions,account,stored_data)
        end
    end
    private_class_method :navigate

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
    private_class_method :navigation_input

    def pick_an_account(separated_accounts)
        puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        puts "Pick an account to view"
        separated_accounts.each_with_index do |name,i|
            puts "[#{i+1}] #{name}"
        end
        input = navigation_input(("1".."#{separated_accounts.size}").to_a)
        return input == false ? false : separated_accounts[input.to_i-1]
    end
    private_class_method :pick_an_account

    def pick_an_action(account_name)
        actions = {
            "Recurring Events" => :recurring_events,
            "Past Month(s) Report" => :previous_months_report,
            "Current Month Report" => :current_month_report,
            "Future Month Report" => :future_month_report
        }
        puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        puts "Pick a data view for this account (#{account_name})"
        actions.keys.each_with_index do |name,i|
            puts "[#{i+1}] #{name}"
        end
        action_options = ("1"..actions.size.to_s).to_a
        input = navigation_input(action_options)
        input = actions[actions.keys[input.to_i-1]] if action_options.include?(input)
        return input
    end
    private_class_method :pick_an_action

    def pick_recurring_action(account_name)
        puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        puts "View Recurring Events (#{account_name})"
        puts "[1] Current Events"
        puts "[2] Legacy Events"
        puts "[3] More Options"
        input = navigation_input(("1".."3").to_a)
        return input
    end
    private_class_method :pick_recurring_action
end
