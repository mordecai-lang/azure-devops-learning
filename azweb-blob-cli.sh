  GNU nano 7.2                                                                                                                                                                                                                        blob-host.sh
#variables
variables(){
        echo "Fill in for automation:"
        read -p "1.Subscription ID: " sub-ID
        read -p "2.Resource Group: " RG
        read -p "Location: " location
        read -p "Storage Account: " storage-account
        read -p "Front Door Name: " FD
}

#Login to Azure
azure-login(){
        az login
}

#Set Subscriotion
Set-subscription(){
        echo "Setting Subscription..."
        az account set --subscription "$sub-ID" && echo "Set success."|| echo "Failed to Set/invalid subscription ID!"
}


#Create Resource Group
resource-group(){
        az group create --name "$RG" --location "$location"
}


#Create private storage Account
private-storage-ac(){
        az storage account create --name "$storage-account" --resource-group "$RG" --location "$location" --sku \
  Standard_LRS --kind StorageV2 --enable-private-endpoint true --https-only true && \
  echo "Private storage account created succesfully" || echo "Unable to create private storage account!"
}


#Enable Static Website
enable-static-web(){
        az storage blob service-properties update --account-name "$storage-account" --static-website --index-document \
  index.html --404-document 404.html && echo "Static Web enabled: " || echo "Failed to enable static web"
}

#Upload website files
upload-web-files(){
        echo "Looking for web files directory (website-files) in home directory..."
        cd ~ && cd website-files || echo \
  "Directory Not found, Make sure website-files directory is located in home directory"
        echo "Currently in website-files directory"


        az storage blob upload-batch --account-name "$storage-account" --destination '$web' --source . \
  --auth-mode login
}
vnet-pe(){
        echo "Creating VNet + Subnet..."
        az network vnet create --name "$VNet" --resource-group "$RG" --location --address-prefix 10.0.0.0/16 \
  --subnet-name "$subnet" --subnet-prefix 10.0.1.0/24

        echo "Disabling network policies for subnet"
        az network vnet subnet update --resource-group "$RG" --vnet-name "$VNet" --name "$subnet" \
  --disable-private-endpoint-network-policies true

        echo "Creating Private DNS zone"
        az network private-dns zone create --resource-group "RG" --name "$DNS-zone"

        echo "Linking DNS with VNet"
        az network private-dns link vnet create --resource-group "$RG" --zone-name "$DNS-zone" --name vnet-link \
  --virtual-network "$VNet" --registration-enabled false

        echo "Getting Storage account ID"
        STORAGE_ID=$(az storage account show --name "$storage" --resource-group "$RG" --query id -o tsv)

        echo "Creating Private endpoint"
        az network private-endpoint create --name blob-private endpoint --resource-group "$RG" --vnet-name "$VNet" \
  --subnet "$subnet" --private-connection-resource-id "$STORAGE_ID" --group-id blob --connection-name blob-connection

        echo "Attaching Private DNS with Private Endpoint"
        az network private-endpoint dns-zone-group create \
  --resource-group "$RG" --endpoint-name blob-private endpoint --name blob-dns-zone-group \
  --private-dns-zone "$DNS-zone" --zone-name "$DNS-zone"


#Configure Front door
front-door(){
        az afd profile create --resource-group "$RG" --name "$FD-profile" --sku Premium_AzureFrontDoor
        az afd endpoint create --resource-group "$RG" --profile-name "$FD-profile" --name "$FD-Endpoint"
        az afd origin-group create --resource-group "$RG" --profile-name "$FD_profile" --origin-group-name "$ORIGIN_GROUP" --probe-request-type GET --probe-protocol Https --probe-path
        az afd origin create --resource-group "$RG" --profile-name "$FD_profile" --origin-group-name \
  "$ORIGIN_GROUP" --origin-name "$ORIGIN_NAME" --host-name "$storage-account".blob.core.windows.net \
  --origin-host-header "$storage-account".blob.core.windows.net --enable-private-link true \
  --private-link-location "$location" --private-link-resource "$STORAGE_ID" --private-link-sub-resource blob

        az network private-endpoint-connection list --resource-group "$RG" --name "$storage" --type \
  Microsoft.Storage/storageAccounts

        read -p "Input Private Endpoint connection ID" PE-ID
        az network private-endpoint-connection approve --id PE-ID
        az afd route create --resource-group "$RG" \
  --profile-name "$FD_PROFILE" --endpoint-name "$FD_ENDPOINT" --route-name default-route --origin-group "$ORIGIN_GROUP" \
  --supported-protocols Https --patterns-to-match "/*" --https-redirect Enabled --forwarding-protocol MatchRequest
}


#Create CDN

cdn(){
        az cdn profile create --name myCdnProfile --resource-group "$RG" --sku Standard_Microsoft

        az cdn endpoint create --name myCdnEndpoint --profile-name myCdnProfile --resource-group myResourceGroup \
  --origin "$storage-account".blob.core.windows.net --origin-host-header "$storage-account".blob.core.windows.net
}

output-url(){
        az afd endpoint show --resource-group "$RG" --profile-name "$FD_PROFILE" --endpoint-name "$FD_ENDPOINT" --query hostName -o tsv
}




