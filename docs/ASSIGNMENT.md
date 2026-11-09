The Product Analytics team has requested a curated analytics dataset to support operational and executive reporting related to insurance policy performance.

The business is specifically looking to answer questions such as:

- Which policy types are generating the highest loss ratios? 
- How do claims and payments trend across different policy segments? 
- Which customers or policy groups may represent elevated financial risk? 
- How can leadership monitor policy profitability and claims exposure over time? 

Your task is to design and implement a scalable, maintainable solution that transforms the provided raw datasets into a curated reporting layer suitable for analytics and downstream business consumption.

The expectation is not perfection or enterprise-scale completeness, but rather a thoughtful engineering approach that demonstrates technical capability, sound judgment, and clear communication of design decisions and tradeoffs.

You are encouraged to use the tools, platforms, and workflows you believe are most appropriate for the exercise.

Please implement the solution in Snowflake. A Snowflake trial account may be used for this project if desired, and candidates are encouraged to take advantage of all Snowflake platform capabilities and supporting engineering tools where appropriate.

In addition to the data engineering solution, demonstrate how you would operate this workload in a production Snowflake environment.  

Include:
- A simple RBAC design for engineers, analysts, and a service/process role
- Warehouse configuration and rationale, including auto-suspend/auto-resume
- A resource monitor or other approach to managing compute cost
- Appropriate database/schema/object grants
- At least one example of how sensitive data could be protected using Snowflake security capabilities
- A brief description of how you would monitor, troubleshoot, and deploy this solution across environments

You do not need to build an enterprise-complete administration framework. We are interested in your design choices and reasoning.

Senior Data Engineer Take-Home Dataset

Included Files:
- customers.csv
- policies.csv
- claims.csv
- payments.csv
- endorsements.json

Intentional Data Quality Issues:
- Duplicate records
- Orphan foreign keys
- Missing values
- Negative financial amounts
- Invalid date relationships
