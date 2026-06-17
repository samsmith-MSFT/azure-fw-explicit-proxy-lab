# Tear down the Azure Firewall explicit proxy lab
# Deletes the whole resource group. Run when finished testing.
az group delete -n rg-fwproxy-lab --yes --no-wait
Write-Host "Deletion of rg-fwproxy-lab started."
