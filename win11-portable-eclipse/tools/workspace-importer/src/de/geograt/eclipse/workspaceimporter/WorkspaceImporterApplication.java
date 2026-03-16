package de.geograt.eclipse.workspaceimporter;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

import org.eclipse.core.resources.IProject;
import org.eclipse.core.resources.IProjectDescription;
import org.eclipse.core.resources.IResource;
import org.eclipse.core.resources.IWorkspace;
import org.eclipse.core.resources.IWorkspaceRoot;
import org.eclipse.core.resources.ResourcesPlugin;
import org.eclipse.core.runtime.IPath;
import org.eclipse.core.runtime.NullProgressMonitor;
import org.eclipse.core.runtime.Path;
import org.eclipse.equinox.app.IApplication;
import org.eclipse.equinox.app.IApplicationContext;

public final class WorkspaceImporterApplication implements IApplication {

    @Override
    public Object start(IApplicationContext context) throws Exception {
        String[] args = (String[]) context.getArguments().get(IApplicationContext.APPLICATION_ARGS);
        List<File> projectDirs = parseProjectDirs(args);
        if (projectDirs.isEmpty()) {
            throw new IllegalArgumentException("No project directories were provided. Use -importProject <path>.");
        }

        IWorkspace workspace = ResourcesPlugin.getWorkspace();
        IWorkspaceRoot root = workspace.getRoot();
        NullProgressMonitor monitor = new NullProgressMonitor();

        for (File projectDir : projectDirs) {
            File projectFile = new File(projectDir, ".project");
            if (!projectFile.isFile()) {
                throw new IllegalArgumentException("Missing .project file: " + projectFile.getAbsolutePath());
            }

            IPath projectFilePath = Path.fromOSString(projectFile.getAbsolutePath());
            IProjectDescription description = workspace.loadProjectDescription(projectFilePath);
            description.setLocation(Path.fromOSString(projectDir.getAbsolutePath()));

            IProject project = root.getProject(description.getName());
            if (!project.exists()) {
                project.create(description, monitor);
            }

            if (!project.isOpen()) {
                project.open(monitor);
            }

            project.refreshLocal(IResource.DEPTH_INFINITE, monitor);
        }

        workspace.save(true, monitor);
        return IApplication.EXIT_OK;
    }

    @Override
    public void stop() {
        // No-op.
    }

    private static List<File> parseProjectDirs(String[] args) {
        List<File> projectDirs = new ArrayList<>();
        for (int i = 0; i < args.length; i++) {
            if (!"-importProject".equals(args[i])) {
                continue;
            }
            if (i + 1 >= args.length) {
                throw new IllegalArgumentException("Missing value after -importProject.");
            }

            File projectDir = new File(args[++i]).getAbsoluteFile();
            if (!projectDir.isDirectory()) {
                throw new IllegalArgumentException("Project directory not found: " + projectDir.getAbsolutePath());
            }
            projectDirs.add(projectDir);
        }
        return projectDirs;
    }
}
