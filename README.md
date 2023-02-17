# terraeasy
Easy Terraform wrapper

## Purpose / main ideas

### 1. Make terraform DRY
Avoid repeating of terraform code across environments, put all common (across environments) resources in
`common` directory, put differentiating variables and resources to environment specific directories (eg. `stage` or `prod`)

### 2. Use goodness for terraform graphs
Unlike terragrunt, idea here is NOT to split infrastructure to as many states as possible, this allows easier
consumption of resource outputs within a single apply / plan

### 3. Keep it simple and expandable
It's bash, how much easier can it get? :)

### 4. Got a lot of custom modules in git? Save time!
*This is optional* to use this, in `terraeasy.sh`
`terraeasy.sh` will clone / pull given git repository on every run. Idea behind this is that when there is a repository
with multiple custom terraform modules, we clone/pull it once (effectively cache) and refer to module source by relative
path (prefixed with `../.terraform-modules/`)

## How does it work

`terraeasy.sh` has built in help, so just run it without any arguments for help

When you run `terraeasy.sh` for a given environment (eg. stage) it will:
1. Create working directory (`tf-working-dir` by default)
2. Create symbolic links for `*tf*` files (so eg. .tf, .tfvars) from `common` and `stage` (in this example) to `tf-working-dir`
3. Will run `terraform init -reconfigure` with `-chdir tf-working-dir`
4. Will run your command (eg. plan or apply) with `-chdir tf-working-dir` and will include `state.tfvars` from `stage` directory
 
