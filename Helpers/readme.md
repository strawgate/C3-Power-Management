### Enable the Power Inspectors

You first must instruct the BigFix agent to begin tracking power states. You can do this in the C3 Power Management site you can use the fixlet: Config - BigFix Power Tracking - Enable Inspectors - Windows

Tracking starts the moment it is enabled and the client stores two weeks of power state data by default.

### Enable the Historical Power State Analysis

Now we must gather the power states from the endpoints. To do this simply enable the Analysis: Power - Historical States - Win\Mac

### Run the Script!

The script itself takes a couple parameters:

Resolution = The resolution of the analysis (default = 5 minutes)
Days = The number of days of usage to analyze (default = 7 days)

BigFix = FQDN of your BigFix Server
Computer Group = Name of the Computer Group to limit results to

Outfile = Name of the report to save