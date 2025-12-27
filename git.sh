#push-project(){
#	read -p "Enter File name" files
#	read -p "Enter directory name" dir
#	read -p "Enter repository name" repo_name
#	mkdir "$dir" && cd "$dir"
#	echo "Git script test" >> "$files"
#	echo "Initialising git "
#	git init || echo "Unable to initialise"
#	echo "Adding files"
#	echo "Adding files"
#	git add ./"$files" || echo "Unable to add"
#	git commit -m "Test push"
#
#	echo "Connecting to local repo"
#	git branch -M main
#	git remote add origin https://github.com/mordecai-lang/"$repo_name".git
#
#	echo "Push"
#	git push -u origin main
#}
#push-project

push-project(){
#    read -p "Enter file name: " files
#    read -p "Enter directory name: " dir
    read -p "Enter repository name (on GitHub): " repo_name

#    mkdir "$dir" && cd "$dir" || { echo "Failed to create or enter directory"; exit 1; }
    echo "Initializing Git repository..."
    git init || { echo "Unable to initialize Git"; exit 1; }

    echo "Adding file..."
    git add . || { echo "Unable to add file"; exit 1; }

    git commit -m "Test push"

    echo "Setting branch and remote..."
    git branch -M main
    git remote add origin https://github.com/mordecai-lang/"$repo_name".git

    echo "Pulling latest changes from remote (if any)..."
    git pull origin main --rebase

    echo "Pushing to GitHub..."
    git push -u origin main
}
push-project
