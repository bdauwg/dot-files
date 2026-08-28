function azlogin

    az login
    wait
    az acr login --name ardcr1
end
