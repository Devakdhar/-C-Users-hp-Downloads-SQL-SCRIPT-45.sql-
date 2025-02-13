--- Identify customers with low credit scores and high-risk loans to predict potential defaults and prioritize risk mitigation strategies.
SELECT 
    high_risk.customer_id, 
    high_risk.name, 
    high_risk.credit_score, 
    COUNT(DISTINCT high_risk.loan_id) AS total_loans, 
    SUM(high_risk.loan_amount) AS total_debt, 
    COUNT(CASE WHEN high_risk.transaction_type = 'Penalty' OR high_risk.status = 'Failed' THEN 1 END) AS missed_payments,
    MAX(high_risk.default_risk_numeric) AS max_default_risk,
    ROUND(
        ((600 - COALESCE(high_risk.credit_score, 600)) / 600) + 
        MAX(high_risk.default_risk_numeric) + 
        (COUNT(CASE WHEN high_risk.transaction_type = 'Penalty' OR high_risk.status = 'Failed' THEN 1 END) * 0.5),
    2) AS risk_score
FROM (
    SELECT 
        c.customer_id, 
        c.name, 
        c.credit_score, 
        l.loan_id, 
        l.loan_amount, 
        CASE 
            WHEN l.default_risk = 'High' THEN 1.0
            WHEN l.default_risk = 'Medium' THEN 0.5
            WHEN l.default_risk = 'Low' THEN 0.2
            ELSE 0 
        END AS default_risk_numeric,
        COALESCE(t.transaction_type, 'No Transactions') AS transaction_type, 
        COALESCE(t.status, 'No Transactions') AS status
    FROM cross_river_bank.customer_table c
    JOIN cross_river_bank.loan_table l ON c.customer_id = l.customer_id
    LEFT JOIN cross_river_bank.transaction_table t ON l.loan_id = t.loan_id
    WHERE c.credit_score < 600 
      AND (l.default_risk = 'High' OR CAST(l.default_risk AS DECIMAL(3,2)) > 0.7) 
) AS high_risk
GROUP BY high_risk.customer_id, high_risk.name, high_risk.credit_score
ORDER BY risk_score DESC
LIMIT 1000;
SELECT 
    customer_id,
    name,
    credit_score,
    risk_category,
    active_loans
FROM 
    cross_river_bank.customer_table
WHERE 
    credit_score < 600 
    AND risk_category = 'High';
--- Determine the most popular loan purposes and their associated revenues to align financial products with customer demands
SELECT 
    l.loan_purpose,
    COUNT(l.loan_id) AS loan_count,
    COALESCE(SUM(CASE 
            WHEN t.transaction_type = 'EMI Payment' AND t.status = 'Successful' 
            THEN t.transaction_amount 
            ELSE 0 
        END), 0) AS total_revenue,
    ROUND(AVG(c.income), 2) AS avg_income,
    ROUND(AVG(c.credit_score), 2) AS avg_credit_score
FROM cross_river_bank.loan_table l
JOIN cross_river_bank.customer_table c ON l.customer_id = c.customer_id
LEFT JOIN cross_river_bank.transaction_table t ON l.loan_id = t.loan_id
GROUP BY l.loan_purpose
ORDER BY loan_count DESC, total_revenue DESC;
SELECT 
    loan_purpose, 
    COUNT(loan_id) AS number_of_loans, 
    SUM(loan_amount) AS total_revenue  
FROM 
    cross_river_bank.loan_table
GROUP BY 
    loan_purpose         
ORDER BY 
    total_revenue DESC;  
--- Detect transactions that exceed 30% of their respective loan amounts to flag potential fraudulent activities
SELECT 
    t.transaction_id,
    t.loan_id,
    t.customer_id,
    t.transaction_date,
    t.transaction_amount,
    l.loan_amount,
    ROUND((t.transaction_amount / NULLIF(l.loan_amount, 0)) * 100, 2) AS percentage_of_loan,
    t.transaction_type,
    t.status,
    COALESCE(c.risk_category, 'Unknown') AS risk_category,
    CASE 
        WHEN t.transaction_amount > (l.loan_amount * 0.5) THEN 'HIGH FRAUD RISK'
        WHEN t.transaction_amount > (l.loan_amount * 0.3) AND COALESCE(c.risk_category, 'Unknown') = 'High' 
             THEN 'MEDIUM FRAUD RISK'
        WHEN t.transaction_amount > (l.loan_amount * 0.3) AND (t.transaction_type = 'Prepayment' OR t.transaction_type = 'Cash') 
             THEN 'SUSPICIOUS TRANSACTION'
        ELSE 'NORMAL'
    END AS fraud_flag
FROM cross_river_bank.transaction_table t
JOIN cross_river_bank.loan_table l ON t.loan_id = l.loan_id
JOIN cross_river_bank.customer_table c ON l.customer_id = c.customer_id
WHERE t.transaction_amount > (l.loan_amount * 0.3)
ORDER BY fraud_flag DESC, t.transaction_amount DESC;
SELECT 
    t.transaction_id, 
    t.loan_id, 
    t.customer_id, 
    t.transaction_date, 
    t.transaction_amount, 
    l.loan_amount,  
    CASE 
        WHEN t.transaction_amount > 0.3 * l.loan_amount THEN 'High-Value Transaction' 
        ELSE 'Normal Transaction' 
    END AS transaction_flag
FROM 
    cross_river_bank.transaction_table t
JOIN 
    cross_river_bank.loan_table l ON t.loan_id = l.loan_id  
WHERE 
    t.transaction_amount > 0.3 * l.loan_amount;
--- Analyze the number of missed EMIs per loan to identify loans at risk of default and suggest intervention strategies
SELECT 
    l.loan_id,
    l.customer_id,
    l.loan_amount,
    l.loan_status,
    COUNT(CASE WHEN t.transaction_type = 'Missed EMI' THEN 1 END) AS missed_emi_count,
    c.credit_score,
    c.risk_category,
    CASE 
        WHEN COUNT(CASE WHEN t.transaction_type = 'Missed EMI' THEN 1 END) >= 3 
             THEN 'HIGH RISK - Immediate Intervention Needed'
        WHEN COUNT(CASE WHEN t.transaction_type = 'Missed EMI' THEN 1 END) = 2 
             THEN 'MEDIUM RISK - Payment Reminder Required'
        WHEN COUNT(CASE WHEN t.transaction_type = 'Missed EMI' THEN 1 END) = 1 
             THEN 'LOW RISK - Soft Reminder'
        ELSE 'ON TRACK'
    END AS intervention_strategy
FROM cross_river_bank.loan_table l
JOIN cross_river_bank.customer_table c ON l.customer_id = c.customer_id
LEFT JOIN cross_river_bank.transaction_table t ON l.loan_id = t.loan_id
GROUP BY l.loan_id, l.customer_id, l.loan_amount, l.loan_status, c.credit_score, c.risk_category
ORDER BY missed_emi_count DESC;
--- Examine the geographical distribution of loan disbursements to assess regional trends and business opportunities.
SELECT 
    SUBSTRING_INDEX(c.address, ',', -1) AS region, 
    COUNT(l.loan_id) AS total_loans,
    SUM(l.loan_amount) AS total_loan_amount,
    ROUND(AVG(l.loan_amount), 2) AS avg_loan_amount,
    ROUND(AVG(c.income), 2) AS avg_income,
    ROUND(AVG(c.credit_score), 2) AS avg_credit_score,
    COUNT(CASE WHEN l.loan_status = 'Defaulted' THEN 1 END) AS defaulted_loans,
    ROUND((COUNT(CASE WHEN l.loan_status = 'Defaulted' THEN 1 END) / COUNT(l.loan_id)) * 100, 2) AS default_rate,
    CASE 
        WHEN COUNT(l.loan_id) > 1000 AND ROUND((COUNT(CASE WHEN l.loan_status = 'Defaulted' THEN 1 END) / COUNT(l.loan_id)) * 100, 2) < 5 
             THEN 'High-Growth Market'
        WHEN COUNT(l.loan_id) > 500 AND ROUND((COUNT(CASE WHEN l.loan_status = 'Defaulted' THEN 1 END) / COUNT(l.loan_id)) * 100, 2) BETWEEN 5 AND 10 
             THEN 'Moderate Risk - Potential Market'
        ELSE 'High Risk - Limited Opportunity'
    END AS business_opportunity
FROM cross_river_bank.loan_table l
JOIN cross_river_bank.customer_table c ON l.customer_id = c.customer_id
GROUP BY region
ORDER BY total_loan_amount DESC, default_rate ASC;
---- List customers who have been associated with Cross River Bank for over five years and evaluate their loan activity to design loyalty programs.
SELECT *,
    CASE 
        WHEN years_with_bank >= 10 AND successful_repayment_rate >= 90 
             THEN 'Platinum Loyalty - Premium Benefits'
        WHEN years_with_bank >= 7 AND successful_repayment_rate >= 85 
             THEN 'Gold Loyalty - Exclusive Discounts'
        WHEN years_with_bank >= 5 
             THEN 'Silver Loyalty - Special Offers'
        ELSE 'Standard Customer'
    END AS loyalty_tier
FROM (
    SELECT 
        c.customer_id,
        c.name,
        c.customer_since_temp, 
        TIMESTAMPDIFF(YEAR, c.customer_since_temp, CURDATE()) AS years_with_bank, 
        COUNT(l.loan_id) AS total_loans,
        COALESCE(SUM(l.loan_amount), 0) AS total_loan_amount,
        ROUND(COALESCE(AVG(l.loan_amount), 0), 2) AS avg_loan_amount,
        COUNT(CASE WHEN l.loan_status = 'Closed' THEN 1 END) AS successfully_closed_loans,
        COUNT(CASE WHEN l.loan_status = 'Defaulted' THEN 1 END) AS defaulted_loans,
        ROUND(
          (CASE 
            WHEN COUNT(l.loan_id) > 0 
            THEN (COUNT(CASE WHEN l.loan_status = 'Closed' THEN 1 END) / NULLIF(COUNT(l.loan_id), 0)) * 100
            ELSE 0
          END), 2) AS successful_repayment_rate
    FROM cross_river_bank.customer_table c
    LEFT JOIN cross_river_bank.loan_table l 
        ON c.customer_id = l.customer_id
    GROUP BY c.customer_id, c.name, c.customer_since_temp
) AS CustomerLoanStats  
WHERE years_with_bank > 5  
ORDER BY years_with_bank DESC, successful_repayment_rate DESC;
--- Age-Based Loan Analysis: Analyze loan amounts disbursed to customers of different age groups to design targeted financial products.
SELECT 
    CASE 
        WHEN c.age < 25 THEN 'Under 25'
        WHEN c.age BETWEEN 25 AND 34 THEN '25-34'
        WHEN c.age BETWEEN 35 AND 44 THEN '35-44'
        WHEN c.age BETWEEN 45 AND 54 THEN '45-54'
        WHEN c.age BETWEEN 55 AND 64 THEN '55-64'
        ELSE '65 and above'
    END AS age_group,
    SUM(l.loan_amount) AS total_loan_amount,
    COUNT(l.loan_id) AS number_of_loans     
FROM 
    cross_river_bank.customer_table c
JOIN 
    cross_river_bank.loan_table l ON c.customer_id = l.customer_id 
GROUP BY 
    CASE 
        WHEN c.age < 25 THEN 'Under 25'
        WHEN c.age BETWEEN 25 AND 34 THEN '25-34'
        WHEN c.age BETWEEN 35 AND 44 THEN '35-44'
        WHEN c.age BETWEEN 45 AND 54 THEN '45-54'
        WHEN c.age BETWEEN 55 AND 64 THEN '55-64'
        ELSE '65 and above'
    END
ORDER BY 
    age_group;
---- Examine transaction patterns over years and months to identify seasonal trends in loan repayments.
SELECT 
    YEAR(STR_TO_DATE(t.transaction_date, '%Y-%m-%d')) AS transaction_year, 
    MONTH(STR_TO_DATE(t.transaction_date, '%Y-%m-%d')) AS transaction_month,
    COUNT(t.transaction_id) AS total_transactions, 
    SUM(t.transaction_amount) AS total_repayments  
FROM 
    cross_river_bank.transaction_table t
LEFT JOIN 
    cross_river_bank.loan_table l ON t.loan_id = l.loan_id  
WHERE 
    t.transaction_date IS NOT NULL 
    AND t.loan_id IS NOT NULL 
GROUP BY 
    YEAR(STR_TO_DATE(t.transaction_date, '%Y-%m-%d')), 
    MONTH(STR_TO_DATE(t.transaction_date, '%Y-%m-%d'))                      
ORDER BY 
    transaction_year, 
    transaction_month;
--- Repayment History Analysis: Rank loans by repayment performance using window functions.
WITH LoanPerformance AS (
    SELECT 
        l.loan_id, 
        l.customer_id, 
        l.loan_amount, 
        l.loan_date, 
        l.loan_status, 
        l.interest_rate, 
        l.loan_purpose, 
        l.collateral, 
        l.default_risk,
        COUNT(CASE WHEN t.transaction_type = 'EMI Payment' AND t.status = 'Successful' THEN 1 END) AS successful_payments,
        COUNT(CASE WHEN t.transaction_type = 'Missed EMI' THEN 1 END) AS missed_payments,
        ROUND(
            (COUNT(CASE WHEN t.transaction_type = 'EMI Payment' AND t.status = 'Successful' THEN 1 END) 
            / NULLIF(COUNT(t.transaction_id), 0)) * 100, 2
        ) AS repayment_success_rate
    FROM cross_river_bank.loan_table l
    LEFT JOIN cross_river_bank.transaction_table t 
        ON l.loan_id = t.loan_id
    GROUP BY l.loan_id, l.customer_id, l.loan_amount, l.loan_date, l.loan_status, 
             l.interest_rate, l.loan_purpose, l.collateral, l.default_risk
)
SELECT 
    loan_id, 
    customer_id, 
    loan_amount, 
    loan_date, 
    loan_status, 
    interest_rate, 
    loan_purpose, 
    collateral, 
    default_risk,
    successful_payments, 
    missed_payments, 
    repayment_success_rate,
    RANK() OVER (ORDER BY repayment_success_rate DESC) AS repayment_rank
FROM LoanPerformance
ORDER BY repayment_rank;
--- Credit Score vs. Loan Amount: Compare average loan amounts for different credit score ranges.
SELECT 
    CASE 
        WHEN c.credit_score >= 800 THEN 'Excellent (800+)'
        WHEN c.credit_score BETWEEN 740 AND 799 THEN 'Very Good (740-799)'
        WHEN c.credit_score BETWEEN 670 AND 739 THEN 'Good (670-739)'
        WHEN c.credit_score BETWEEN 580 AND 669 THEN 'Fair (580-669)'
        ELSE 'Poor (<580)'
    END AS credit_score_category,
    COUNT(l.loan_id) AS total_loans,
    ROUND(AVG(l.loan_amount), 2) AS avg_loan_amount
FROM cross_river_bank.customer_table c
JOIN cross_river_bank.loan_table l 
    ON c.customer_id = l.customer_id
GROUP BY credit_score_category
ORDER BY FIELD(credit_score_category, 'Excellent (800+)', 'Very Good (740-799)', 'Good (670-739)', 'Fair (580-669)', 'Poor (<580)');
--- Top Borrowing Regions: Identify regions with the highest total loan disbursements.
SELECT 
    c.address AS region,  
    COUNT(l.loan_id) AS total_loans, 
    SUM(l.loan_amount) AS total_loan_disbursement
FROM cross_river_bank.customer_table c
JOIN cross_river_bank.loan_table l 
    ON c.customer_id = l.customer_id
GROUP BY c.address
ORDER BY total_loan_disbursement DESC
LIMIT 10;  
---- Early Repayment Patterns: Detect loans with frequent early repayments and their impact on revenue.
SELECT 
    l.loan_id, 
    l.loan_amount, 
    COALESCE(SUM(t.transaction_amount), 0) AS total_repaid_early_payments,
    COALESCE((SUM(t.transaction_amount) * 100.0) / NULLIF(l.loan_amount, 0), 0) AS repayment_percentage
FROM cross_river_bank.loan_table l
LEFT JOIN cross_river_bank.transaction_table t 
    ON l.loan_id = t.loan_id 
    AND t.transaction_type = 'prepayment'
GROUP BY l.loan_id, l.loan_amount
HAVING total_repaid_early_payments > 0
ORDER BY repayment_percentage DESC
LIMIT 1000;

