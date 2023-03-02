# Get the branch name that you are currently on in git
git-current-branch() 
{
  git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,'
}
