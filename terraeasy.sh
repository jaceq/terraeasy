#!/bin/bash
# Disable quoting of arrays expansion
# shellcheck disable=SC2068

##TERRAEASY##

if [ ! -f .terraeasy-config ]; then
  echo ".terraeasy-config not found!"
  echo "Please create config, refer to .terraeasy-config.example"
  exit 1
fi

# shellcheck source=.terraeasy-config
source .terraeasy-config

# Export / set terraform common_prefix variable, useful
# for using templates from common directory.
export TF_VAR_common_prefix="${TERRAEASY_COMMON_BASE_DIR}-"

print_help(){
  echo "  Usage:"
  echo "    $0 [options]"
  echo ""
  echo "    -c|--command       -- terraform command, eg. apply, plan or virtual command eg. 'auto-apply'"
  echo "    -e|--environment   -- working environment, eg. prod, stage or dev"
  echo "    -l|--lint          -- lint terraform, requires installed tflint (in path)"
  echo "    -n|--naked-command -- Quoted(!!) naked command to pass to terraform binary"
  echo "    -s|--silent        -- Show only output from final terraform command (useful for collecting outputs)"
  echo "    -u|--update        -- Self update, pull latest terraeasy.sh from github"
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

error_exit(){
  MESSAGE=$1
  echo "ERROR: $MESSAGE"
  exit 1
}

update_terraeasy(){
  TEMP_DOWNLOAD_LOCATION='/tmp/terraeasy.sh.download'
  if ! stat terraeasy.sh >/dev/null; then
    echo 'terraeasy.sh not found in current directory, aborting!'
    exit 1
  fi
  if which curl >/dev/null; then
    echo 'Found curl, updating...'
    curl https://"${TERRAEASY_GIT_REPOSITORY_RAW}/terraeasy.sh" > "$TEMP_DOWNLOAD_LOCATION" || error_exit 'failed download terraeasy.sh with curl'
  elif which wget >/dev/null; then
    echo 'Found wget, updating...'
    wget https://"${TERRAEASY_GIT_REPOSITORY_RAW}"/terraeasy.sh -O "$TEMP_DOWNLOAD_LOCATION" || error_exit 'failed download terraeasy.sh with wget'
  else
    echo 'neither curl nor wget found, aborting update!'
    exit 1
  fi
  if grep -q '##TERRAEASY##' "$TEMP_DOWNLOAD_LOCATION"; then
    mv "$TEMP_DOWNLOAD_LOCATION" terraeasy.sh
    chmod 755 terraeasy.sh
  else
    error_exit "Downloaded file is incorrect! Downloaded copy left at: $TEMP_DOWNLOAD_LOCATION"
  fi
}

update_modules(){
  # If folder exists try git pull
  if [ -d "$TERRAEASY_TERRAFORM_MODULES_PATH" ]; then
    git -C "$TERRAEASY_TERRAFORM_MODULES_PATH" pull || display_warning "Git pull of modules failed!"
  else
    git clone "$TERRAEASY_TERRAFORM_MODULES_GIT_REPOSITORY" "$TERRAEASY_TERRAFORM_MODULES_PATH"
  fi
}

link_working_dir(){
  BASE_DIR="$1"
  for FILE in "$BASE_DIR"/*tf*; do
    NEW_FILE="${FILE//\//-}"
    ln -s "${PWD}/${FILE}" "${TERRAEASY_WORKING_DIR}/${NEW_FILE}"
  done
}

ARGS=("$@")

while (($#)); do
  case $1 in
    -c|--command)
      shift
      COMMAND="$1"
      VALID='true'
      ;;
    -e|--environment)
      shift
      ENV="$1"
      ;;
    -l|--lint)
      LINT='true'
      VALID='true'
      ;;
    -n|--naked-command)
      shift
      NAKED_COMMAND="$1"
      VALID='true'
      ;;
    -s|--silent)
      SILENT='true'
      ;;
    -u|--update)
      UPDATE='true'
      VALID='true'
      ;;
    *)
      printf '%s\n' "Unknown option $1" >&2
      print_help
      exit 1
  esac
  shift
done

if [ -z "$VALID" ]; then
  echo 'No command was given, need: -c, -n, -l or -u'
  print_help
  exit 1
fi

# -u|--update can be the only option
if [ -n "$UPDATE" ] && [ ${#ARGS[@]} -gt 1 ]; then
  error_exit '-u|--update option cannot be combined with other options'
elif [ -n "$UPDATE" ]; then
  update_terraeasy
  echo 'Update complete!'
  exit 0
fi

if [ -n "$COMMAND" ] && [ -n "$NAKED_COMMAND" ]; then
  echo 'Cannot use -c and -n arguments at the same time, only one is allowed'
  print_help
  exit 1
fi

if [ -z "$ENV" ]; then
  echo 'Environment is not defined.'
  print_help
  exit 1
fi

# Check is given environment exists
if ! ls -d "${ENV}" 1>/dev/null 2>&1; then
  echo "Given environment ${ENV} not found!"
  print_help
  exit 1
fi

# Implement silent option
if [ -n "$SILENT" ]; then
  exec 3>&1 &>/dev/null
else
  exec 3>&1
fi

printf 'Working env: %s\n' "$ENV"

# Link contents of common and chosen environment in working dir
mkdir -p "$TERRAEASY_WORKING_DIR"
rm -f "$TERRAEASY_WORKING_DIR"/*.tf*
link_working_dir "$TERRAEASY_COMMON_BASE_DIR"
link_working_dir "$ENV"

if [ -n "$LINT" ]; then
  echo 'Found "-l or --lint" parameter, doing only linting'
  tflint --chdir="$TERRAEASY_WORKING_DIR"
  rm -f "$TERRAEASY_WORKING_DIR"/*.tf*
  exit
fi

if [ -n "$TERRAEASY_TERRAFORM_MODULES_GIT_REPOSITORY" ]; then
  update_modules
fi

terraform -chdir="$TERRAEASY_WORKING_DIR" init -backend-config="${ENV}-backend.tfvars" -reconfigure || error_exit 'terraform backend configuration failed'

CMD_ARGS=()

if [ -n "$NAKED_COMMAND" ]; then
  CMD_ARGS=("$NAKED_COMMAND")
elif [ "$COMMAND" == 'auto-apply' ]; then
  PLAN_FILE="TF_PLAN_$(date +%s).tfplan"
  CMD_ARGS+=('plan' "-out=${PLAN_FILE}" "-var-file=${ENV}-state.tfvars")
  echo "Running: terraform -chdir=$TERRAEASY_WORKING_DIR ${CMD_ARGS[*]}"
  terraform -chdir="$TERRAEASY_WORKING_DIR" ${CMD_ARGS[@]} || error_exit 'terraform auto-apply (plan) failed'
  CMD_ARGS=('apply' '-auto-approve' "$PLAN_FILE")
else
  # run FMT on normal commands
  terraform fmt "$TERRAEASY_WORKING_DIR"
  CMD_ARGS+=("$COMMAND" "-var-file=${ENV}-state.tfvars")
fi

echo "Running: terraform -chdir=$TERRAEASY_WORKING_DIR ${CMD_ARGS[*]}"
terraform -chdir="$TERRAEASY_WORKING_DIR" ${CMD_ARGS[@]} >&3 || error_exit "terraform failed with args: ${CMD_ARGS[*]}"

# Clean up working dir
rm -f "$TERRAEASY_WORKING_DIR"/*.tf*
