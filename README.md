# Salesforce DX Project: Next Steps

Now that youâ€™ve created a Salesforce DX project, whatâ€™s next? Here are some documentation resources to get you started.

## How Do You Plan to Deploy Your Changes?

Do you want to deploy a set of changes, or create a self-contained application? Choose a [development model](https://developer.salesforce.com/tools/vscode/en/user-guide/development-models).

## Configure Your Salesforce DX Project

The `sfdx-project.json` file contains useful configuration information for your project. See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm) in the _Salesforce DX Developer Guide_ for details about this file.

## Read All About It

- [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
- [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)

## 2025-08-26: Patch + Deploy
- Fix Apex comparator, switch to URL.getOrgDomainUrl(), and robust Tooling calls.
- LWC datatable flags use "true"/"false" string literals (LWC template rule).
- Files saved as UTF-8 w/out BOM to avoid XML prolog/Apex leading-char issues.
- Script ensures sandbox auth and deploys automatically.

### Deploy
\\\ash
sf project deploy start --source-dir force-app --target-org ApiVersionUpdaterSandbox
\\\