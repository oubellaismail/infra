do_token = "dop_v1_917abebd892da00c82683a683771e6da078bcf25fdfd71d6884d431ccb07c3c7"
ssh_key_ids = ["50286368"]

allowed_admin_cidrs = ["41.141.62.149/32"] # Use your specific CIDR here

# Sizes for the droplets (optional, will use defaults if not set)
bastion_size = "s-1vcpu-1gb"
staging_frontend_size = "s-1vcpu-2gb"
staging_backend_size = "s-2vcpu-2gb"
production_frontend_size = "s-2vcpu-4gb"
production_backend_size = "s-4vcpu-8gb"


# export TF_API_TOKEN="ij30nzfiz43DqQ.atlasv1.BI5GcJMJ1CSOLQR1qZJtjn6DpeobpW9hG9NDqiEgTTDitGraBm9PZMN05QS4712FFPU"


