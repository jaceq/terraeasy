#!/bin/bash
# Disable quoting of arrays expansion
# shellcheck disable=SC2068

# Optional URL for git repository with terraform modules, refer to README.md
#TERRAFORM_MODULES_GIT_REPOSITORY="<you git repository with custom modules>"

WORKING_DIR="tf-working-dir"
COMMON_BASE_DIR="common"
TERRAFORM_MODULES_PATH="./.terraform-modules"

# Export / set terraform common_prefix variable, useful
# for using templates from common directory.
export TF_VAR_common_prefix="${COMMON_BASE_DIR}-"

print_help(){
  echo "  Usage:"
  echo "    $0 [options]"
  echo ""
  echo "    -c|--command       -- terraform command, eg. apply, plan or virtual command eg. 'auto-apply'"
  echo "    -e|--environment   -- working environment, eg. prod, stage or dev"
  echo "    -l|--lint          -- lint terraform, requires installed tflint (in path)"
  echo "    -n|--naked-command -- Quoted(!!) naked command to pass to terraform binary"
  echo ""
  echo "  Virtual commands:"
  echo ""
  echo "    auto-apply -- Will run plan, save it and then apply, non-interactive, use in pipelines"
  echo ""
}

display_warning(){
  MESSAGE="$1"
  STARTCOLOR="\e[91m";
  ENDCOLOR="\e[0m";
  echo ""
  echo ""
  printf "  $STARTCOLOR%b$ENDCOLOR" "$MESSAGE";
  echo ""
}

update_modules(){
  # If folder exists try git pull
  if [ -d "$TERRAFORM_MODULES_PATH" ]; then
    git -C "$TERRAFORM_MODULES_PATH" pull || display_warning "Git pull of modules failed!"
  else
    git clone "$TERRAFORM_MODULES_GIT_REPOSITORY" "$TERRAFORM_MODULES_PATH"
  fi
}

link_working_dir(){
  BASE_DIR="$1"
  for FILE in "$BASE_DIR"/*tf*; do
    NEW_FILE="${FILE//\//-}"
    ln -s "${PWD}/${FILE}" "${WORKING_DIR}/${NEW_FILE}"
  done
}

while (($#)); do
  case $1 in
    -c|--command)
      shift
      COMMAND="$1"
      ;;
    -e|--environment)
      shift
      ENV="$1"
      ;;
    -l|--lint)
      LINT="true"
      ;;
    -n|--naked-command)
      shift
      NAKED_COMMAND="$1"
      ;;
    *)
      printf '%s\n' "Unknown option $1" >&2
      print_help
      exit 1
  esac
  shift
done

if [ "$COMMAND" == '' ] && [ "$NAKED_COMMAND" == '' ] && [ "$LINT" != "true" ]; then
  #TODO: create a nice info message
  echo 'No command was given'
  print_help
  exit 1
fi

if [ "$COMMAND" != '' ] && [ "$NAKED_COMMAND" != '' ]; then
  echo 'Cannot use -c and -n arguments at the same time, only one is allowed'
  print_help
  exit 1
fi

if [ "$ENV" == "" ]; then
  echo 'Environment is not defined.'
  print_help
  exit 1
fi

printf 'Working env: %s\n' "$ENV"

# Link contents of common and chosen environment in working dir
mkdir -p "$WORKING_DIR"
rm -f "$WORKING_DIR"/*.tf*
link_working_dir "$COMMON_BASE_DIR"
link_working_dir "$ENV"

if [ "$LINT" == "true" ]; then
  echo 'Found "-l or --lint" parameter, doing only linting'
  tflint --chdir="$WORKING_DIR"
  rm -f "$WORKING_DIR"/*.tf*
  exit
fi

#fmt on every run! use base dir and relative to it $ENV dir
terraform fmt "$WORKING_DIR"

if [ -n "$TERRAFORM_MODULES_GIT_REPOSITORY" ]; then
  update_modules
fi

terraform -chdir="$WORKING_DIR" init -backend-config="${ENV}-backend.tfvars" -reconfigure

CMD_ARGS=()

if [ "$NAKED_COMMAND" != '' ]; then
  CMD_ARGS=("$NAKED_COMMAND")
elif [ "$COMMAND" == 'auto-apply' ]; then
  PLAN_FILE="TF_PLAN_$(date +%s).tfplan"
  CMD_ARGS+=('plan' "-out=${PLAN_FILE}" "-var-file=${ENV}-state.tfvars")
  echo "Running: terraform -chdir=$WORKING_DIR ${CMD_ARGS[*]}"
  terraform -chdir="$WORKING_DIR" ${CMD_ARGS[@]}
  CMD_ARGS=('apply' '-auto-approve' "$PLAN_FILE")
else
  CMD_ARGS+=("$COMMAND" "-var-file=${ENV}-state.tfvars")
fi

echo "Running: terraform -chdir=$WORKING_DIR ${CMD_ARGS[*]}"
terraform -chdir="$WORKING_DIR" ${CMD_ARGS[@]}

# Clean up working dir
rm -f "$WORKING_DIR"/*.tf*
