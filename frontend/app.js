const taskForm = document.querySelector("#task-form");
const taskTitle = document.querySelector("#task-title");
const taskList = document.querySelector("#task-list");
const message = document.querySelector("#message");
const refreshButton = document.querySelector("#refresh-button");


function showMessage(text, isError = false) {
    message.textContent = text;
    message.className = isError ? "error" : "success";
}


function createTaskElement(task) {
    const item = document.createElement("li");
    item.className = task.completed ? "task completed" : "task";

    const taskInformation = document.createElement("div");
    taskInformation.className = "task-information";

    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = task.completed;
    checkbox.setAttribute(
        "aria-label",
        `Mark ${task.title} as completed`
    );

    const title = document.createElement("span");
    title.textContent = task.title;

    checkbox.addEventListener("change", async () => {
        try {
            const response = await fetch(`/api/tasks/${task.id}`, {
                method: "PATCH",
                headers: {
                    "Content-Type": "application/json",
                },
                body: JSON.stringify({
                    completed: checkbox.checked,
                }),
            });

            if (!response.ok) {
                throw new Error("Unable to update the task");
            }

            await loadTasks();
            showMessage("Task updated.");
        } catch (error) {
            checkbox.checked = !checkbox.checked;
            showMessage(error.message, true);
        }
    });

    const deleteButton = document.createElement("button");
    deleteButton.type = "button";
    deleteButton.className = "delete-button";
    deleteButton.textContent = "Delete";

    deleteButton.addEventListener("click", async () => {
        try {
            const response = await fetch(`/api/tasks/${task.id}`, {
                method: "DELETE",
            });

            if (!response.ok) {
                throw new Error("Unable to delete the task");
            }

            await loadTasks();
            showMessage("Task deleted.");
        } catch (error) {
            showMessage(error.message, true);
        }
    });

    taskInformation.append(checkbox, title);
    item.append(taskInformation, deleteButton);

    return item;
}


async function loadTasks() {
    taskList.innerHTML = "<li class=\"loading\">Loading tasks...</li>";

    try {
        const response = await fetch("/api/tasks");

        if (!response.ok) {
            throw new Error("Unable to retrieve tasks");
        }

        const tasks = await response.json();
        taskList.replaceChildren();

        if (tasks.length === 0) {
            const emptyMessage = document.createElement("li");
            emptyMessage.className = "empty";
            emptyMessage.textContent = "No tasks yet.";
            taskList.append(emptyMessage);
            return;
        }

        tasks.forEach((task) => {
            taskList.append(createTaskElement(task));
        });
    } catch (error) {
        taskList.replaceChildren();
        showMessage(error.message, true);
    }
}


taskForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    const title = taskTitle.value.trim();

    if (!title) {
        showMessage("Enter a task title.", true);
        return;
    }

    try {
        const response = await fetch("/api/tasks", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({title}),
        });

        if (!response.ok) {
            const result = await response.json();
            throw new Error(result.error || "Unable to create the task");
        }

        taskForm.reset();
        await loadTasks();
        showMessage("Task created.");
        taskTitle.focus();
    } catch (error) {
        showMessage(error.message, true);
    }
});


refreshButton.addEventListener("click", loadTasks);

loadTasks();
