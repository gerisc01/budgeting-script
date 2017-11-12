## Configuration Options

# List all recurring transactions
LIST_RECURRING_PAYMENTS = true
list_recurring_payments = true
# List all the transactions related with recurring transactions
list_recurring_payment_transactions = false
# Print out transaction statistics for the current month
list_current_month = false
# Print out expected transaction statistics for the next month
list_next_month = false

# Define group transactions
def group_transactions
[
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
end

# Accounts that should be separated from everything else
def accounts_to_separate
    ["Joint Account"]
end