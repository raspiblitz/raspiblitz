function set_variables() {
  if [ $# -gt 0 ]; then
    pack=$1
  fi

  if [ $# -gt 1 ]; then
    github_user=$2
  fi

  if [ $# -gt 2 ]; then
    branch=$3
  fi

  if [ $# -gt 4 ]; then
    image_link="$4"
    image_checksum="$5"
  fi

  # Initialize the variables string
  vars=""

  # Add the pack variable if it is defined
  if [ -n "${pack}" ]; then
    vars="$vars -var pack=${pack}"
  fi

  # Add the github_user variable if it is defined
  if [ -n "${github_user}" ]; then
    vars="$vars -var github_user=${github_user}"
  fi

  # Add the branch variable if it is defined
  if [ -n "${branch}" ]; then
    vars="$vars -var branch=${branch}"
  fi

  # Add the image_link variable if it is defined
  if [ -n "${image_link}" ]; then
    vars="$vars -var image_link=${image_link}"
  fi

  # Add the image_checksum variable if it is defined
  if [ -n "${image_checksum}" ]; then
    vars="$vars -var image_checksum=${image_checksum}"
  fi
}
