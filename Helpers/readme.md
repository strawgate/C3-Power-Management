### Enable the Power Inspectors

You first must instruct the BigFix agent to begin tracking power states. You can do this in the C3 Power Management site you can use the fixlet: Config - BigFix Power Tracking - Enable Inspectors - Windows

Tracking starts the moment it is enabled and the client stores two weeks of power state data by default.

### Enable the Historical Power State Analysis

Now we must gather the power states from the endpoints. To do this simply enable the Analysis: Power - Historical States - Win\Mac

### Run the Script!

The script itself takes a couple parameters:

| Variable | Description  | Default |
|---|---|---|
| Resolution |  Data Precision | 5 Minutes |
| Days  |  Number of Days to Analyze | 7 Days|
| BigFix  |  BigFix Server | BigFix |
| Computer Group  | Name of the Computer Group to Query | Required Field |
| OutFile  | Location to place report | MyReport.html |
