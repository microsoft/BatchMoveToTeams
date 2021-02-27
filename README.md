# Batch Move To Teams

> This script is supposed to help large organisations to automate moving their Skype onprem users to Teams. Optimized to work up to 20 times faster on a large number of users in a batch (several thousand users and more) due to parallel processing.

## Features

- Move speed 10-20x faster due to parallel processing
  The script works 10-20 times faster than a traditional one as it executes user moves in parallel as much as possible (but not exceeding the cloud threshold of max user moves     at a time)
- Automatic re-try logic for failed to move users
  For users who failed to move initially (e.g. throttling or some other error) the script will automatically retry them (3 times by default) so you don't have to do it manually
- Move prerequisite checks
  Sort out and report users who don't meet the prerequisites so that the identified missing prerequisites can be corrected for those users.
- Rich reporting capabilities
  Script provides comprehensive reporting for every action or check and will report each user processing and results at various stages of migration and also a summary of the       results, including how many were moved successfully, how many failed to migrate (grouped by the error message) how many were retried, etc. which is really helpful during the     migration to identify bottlenecks and address issues at an early stage

## Limitations

- The script currently does not support the move of Skype onprem users enabled for EV as well as enabling EV capabilities in Teams for moved users. This is currently in testing and will be added soon with a new version of the script.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
