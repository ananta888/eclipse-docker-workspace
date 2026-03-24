package local.win11.portableeclipse.workspaceimporter;

import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.eclipse.core.resources.IProject;
import org.eclipse.core.resources.IProjectDescription;
import org.eclipse.core.resources.IResource;
import org.eclipse.core.resources.IWorkspace;
import org.eclipse.core.resources.IWorkspaceRoot;
import org.eclipse.core.resources.IncrementalProjectBuilder;
import org.eclipse.core.resources.ResourcesPlugin;
import org.eclipse.core.runtime.CoreException;
import org.eclipse.core.runtime.IPath;
import org.eclipse.core.runtime.IStatus;
import org.eclipse.core.runtime.NullProgressMonitor;
import org.eclipse.core.runtime.Path;
import org.eclipse.buildship.core.BuildConfiguration;
import org.eclipse.buildship.core.GradleBuild;
import org.eclipse.buildship.core.GradleCore;
import org.eclipse.buildship.core.SynchronizationResult;
import org.eclipse.jdt.core.IJavaProject;
import org.eclipse.jdt.core.JavaCore;
import org.eclipse.equinox.app.IApplication;
import org.eclipse.equinox.app.IApplicationContext;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.transform.OutputKeys;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;

public final class WorkspaceImporterApplication implements IApplication {

    private static final String USER_CATALOG_NAMESPACE = "urn:oasis:names:tc:entity:xmlns:xml:catalog";
    private static final String AUTO_ENTRY_PREFIX = "portable-eclipse-auto:";

    @Override
    public Object start(IApplicationContext context) throws Exception {
        String[] args = (String[]) context.getArguments().get(IApplicationContext.APPLICATION_ARGS);
        ImportRequest request = parseArgs(args);
        List<File> projectDirs = request.projectDirs();
        if (projectDirs.isEmpty()) {
            throw new IllegalArgumentException("No project directories were provided. Use -importProject <path>.");
        }

        IWorkspace workspace = ResourcesPlugin.getWorkspace();
        IWorkspaceRoot root = workspace.getRoot();
        NullProgressMonitor monitor = new NullProgressMonitor();
        List<IProject> importedProjects = new ArrayList<>();

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
            importedProjects.add(project);
        }

        synchronizeGradleBuilds(request.gradleScanRoots(), importedProjects, monitor);
        registerXsdCatalogEntries(request.xsdScanRoots());
        stabilizeGeneratedSources(workspace, importedProjects, monitor);
        workspace.save(true, monitor);
        return IApplication.EXIT_OK;
    }

    @Override
    public void stop() {
        // No-op.
    }

    private static ImportRequest parseArgs(String[] args) {
        List<File> projectDirs = new ArrayList<>();
        List<File> gradleScanRoots = new ArrayList<>();
        List<File> xsdScanRoots = new ArrayList<>();
        for (int i = 0; i < args.length; i++) {
            String arg = args[i];
            switch (arg) {
                case "-importProject":
                    projectDirs.add(requireDirectoryArg(args, ++i, arg));
                    break;
                case "-scanGradleRoots":
                    gradleScanRoots.add(requireDirectoryArg(args, ++i, arg));
                    break;
                case "-registerXsdFrom":
                    xsdScanRoots.add(requireDirectoryArg(args, ++i, arg));
                    break;
                default:
                    break;
            }
        }

        if (gradleScanRoots.isEmpty()) {
            gradleScanRoots.addAll(projectDirs);
        }
        if (xsdScanRoots.isEmpty()) {
            xsdScanRoots.addAll(gradleScanRoots);
        }

        return new ImportRequest(projectDirs, gradleScanRoots, xsdScanRoots);
    }

    private static File requireDirectoryArg(String[] args, int valueIndex, String optionName) {
        if (valueIndex >= args.length) {
            throw new IllegalArgumentException("Missing value after " + optionName + ".");
        }

        File dir = new File(args[valueIndex]).getAbsoluteFile();
        if (!dir.isDirectory()) {
            throw new IllegalArgumentException("Directory not found for " + optionName + ": " + dir.getAbsolutePath());
        }
        return dir;
    }

    private static void synchronizeGradleBuilds(List<File> scanRoots, List<IProject> importedProjects, NullProgressMonitor monitor) throws CoreException {
        Set<File> gradleRoots = detectGradleRoots(scanRoots, importedProjects);
        for (File gradleRoot : gradleRoots) {
            BuildConfiguration configuration = BuildConfiguration.forRootProjectDirectory(gradleRoot)
                .overrideWorkspaceConfiguration(false)
                .autoSync(false)
                .showConsoleView(true)
                .showExecutionsView(true)
                .build();
            GradleBuild build = GradleCore.getWorkspace().createBuild(configuration);
            SynchronizationResult result = build.synchronize(monitor);
            IStatus status = result.getStatus();
            if (!status.isOK()) {
                throw new CoreException(status);
            }
        }
    }

    private static Set<File> detectGradleRoots(List<File> scanRoots, List<IProject> importedProjects) {
        Set<File> roots = new LinkedHashSet<>();
        for (File scanRoot : scanRoots) {
            roots.addAll(findGradleRootsBelow(scanRoot));
        }
        for (IProject project : importedProjects) {
            if (!project.isAccessible()) {
                continue;
            }
            try {
                if (!project.hasNature("org.eclipse.buildship.core.gradleprojectnature")) {
                    continue;
                }
            } catch (CoreException e) {
                continue;
            }
            File location = project.getLocation() != null ? project.getLocation().toFile() : null;
            if (location != null) {
                roots.addAll(findGradleRootsBelow(location));
                if (isGradleBuildDirectory(location)) {
                    roots.add(location);
                }
            }
        }
        return roots;
    }

    private static Set<File> findGradleRootsBelow(File root) {
        if (root == null || !root.isDirectory()) {
            return Collections.emptySet();
        }

        Set<File> result = new LinkedHashSet<>();
        Deque<File> queue = new ArrayDeque<>();
        queue.add(root);
        while (!queue.isEmpty()) {
            File current = queue.removeFirst();
            if (isIgnoredDirectory(current)) {
                continue;
            }
            if (containsSettingsFile(current)) {
                result.add(current);
                continue;
            }
            if (isGradleBuildDirectory(current)) {
                result.add(current);
            }

            File[] children = current.listFiles(File::isDirectory);
            if (children == null) {
                continue;
            }
            for (File child : children) {
                queue.addLast(child);
            }
        }
        return result;
    }

    private static boolean isIgnoredDirectory(File dir) {
        String name = dir.getName();
        return name.startsWith(".")
            || "build".equalsIgnoreCase(name)
            || "out".equalsIgnoreCase(name)
            || "target".equalsIgnoreCase(name)
            || ".gradle".equalsIgnoreCase(name)
            || ".git".equalsIgnoreCase(name);
    }

    private static boolean containsSettingsFile(File dir) {
        return new File(dir, "settings.gradle").isFile() || new File(dir, "settings.gradle.kts").isFile();
    }

    private static boolean isGradleBuildDirectory(File dir) {
        return new File(dir, "build.gradle").isFile()
            || new File(dir, "build.gradle.kts").isFile()
            || new File(dir, "gradlew").isFile()
            || new File(dir, "gradlew.bat").isFile();
    }

    private static void registerXsdCatalogEntries(List<File> scanRoots) throws Exception {
        Map<String, URI> namespaceMappings = collectXsdEntries(scanRoots);
        if (namespaceMappings.isEmpty()) {
            return;
        }

        File workspaceDir = ResourcesPlugin.getWorkspace().getRoot().getLocation().toFile();
        File catalogDir = new File(workspaceDir, ".metadata/.plugins/org.eclipse.wst.xml.core");
        if (!catalogDir.isDirectory() && !catalogDir.mkdirs()) {
            throw new IOException("Unable to create catalog directory: " + catalogDir.getAbsolutePath());
        }

        File catalogFile = new File(catalogDir, "user_catalog.xml");
        Document document = loadOrCreateCatalog(catalogFile);
        Element root = document.getDocumentElement();
        removeGeneratedEntries(root);

        int counter = 0;
        for (Map.Entry<String, URI> entry : namespaceMappings.entrySet()) {
            String safeId = sanitizeId(entry.getKey(), counter++);
            Element uriNode = document.createElementNS(USER_CATALOG_NAMESPACE, "uri");
            uriNode.setAttribute("id", AUTO_ENTRY_PREFIX + safeId);
            uriNode.setAttribute("name", entry.getKey());
            uriNode.setAttribute("uri", entry.getValue().toASCIIString());
            root.appendChild(uriNode);
        }

        writeDocument(document, catalogFile);
    }

    private static Map<String, URI> collectXsdEntries(List<File> scanRoots) throws Exception {
        Map<String, URI> entries = new LinkedHashMap<>();
        List<File> xsdFiles = new ArrayList<>();
        for (File root : scanRoots) {
            xsdFiles.addAll(findFiles(root, ".xsd"));
        }
        xsdFiles.sort(Comparator.comparing(File::getAbsolutePath));

        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        DocumentBuilder builder = factory.newDocumentBuilder();

        for (File xsdFile : xsdFiles) {
            Document document;
            try {
                document = builder.parse(xsdFile);
            } catch (Exception ignored) {
                continue;
            }
            Element documentElement = document.getDocumentElement();
            if (documentElement == null) {
                continue;
            }
            String namespace = documentElement.getAttribute("targetNamespace");
            if (namespace == null || namespace.isBlank() || entries.containsKey(namespace)) {
                continue;
            }
            entries.put(namespace, xsdFile.toURI());
        }
        return entries;
    }

    private static List<File> findFiles(File root, String suffix) {
        if (root == null || !root.isDirectory()) {
            return Collections.emptyList();
        }
        List<File> files = new ArrayList<>();
        Deque<File> queue = new ArrayDeque<>();
        queue.add(root);
        while (!queue.isEmpty()) {
            File current = queue.removeFirst();
            if (isIgnoredDirectory(current)) {
                continue;
            }
            File[] children = current.listFiles();
            if (children == null) {
                continue;
            }
            for (File child : children) {
                if (child.isDirectory()) {
                    queue.addLast(child);
                } else if (child.getName().endsWith(suffix)) {
                    files.add(child);
                }
            }
        }
        return files;
    }

    private static Document loadOrCreateCatalog(File catalogFile) throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        DocumentBuilder builder = factory.newDocumentBuilder();
        if (catalogFile.isFile()) {
            return builder.parse(catalogFile);
        }

        Document document = builder.newDocument();
        Element root = document.createElementNS(USER_CATALOG_NAMESPACE, "catalog");
        document.appendChild(root);
        return document;
    }

    private static void removeGeneratedEntries(Element root) {
        List<Node> toRemove = new ArrayList<>();
        for (int i = 0; i < root.getChildNodes().getLength(); i++) {
            Node node = root.getChildNodes().item(i);
            if (node instanceof Element element) {
                String id = element.getAttribute("id");
                if (id != null && id.startsWith(AUTO_ENTRY_PREFIX)) {
                    toRemove.add(node);
                }
            }
        }
        for (Node node : toRemove) {
            root.removeChild(node);
        }
    }

    private static String sanitizeId(String value, int index) {
        String sanitized = value.replaceAll("[^A-Za-z0-9._-]", "_");
        if (sanitized.isBlank()) {
            return "entry-" + index;
        }
        return sanitized;
    }

    private static void writeDocument(Document document, File file) throws Exception {
        TransformerFactory transformerFactory = TransformerFactory.newInstance();
        Transformer transformer = transformerFactory.newTransformer();
        transformer.setOutputProperty(OutputKeys.INDENT, "yes");
        transformer.setOutputProperty(OutputKeys.ENCODING, "UTF-8");
        transformer.setOutputProperty("{http://xml.apache.org/xslt}indent-amount", "2");
        transformer.transform(new DOMSource(document), new StreamResult(file));
    }

    private static void stabilizeGeneratedSources(IWorkspace workspace, Collection<IProject> projects, NullProgressMonitor monitor) throws CoreException {
        List<IJavaProject> javaProjects = new ArrayList<>();
        for (IProject project : projects) {
            if (!project.isAccessible()) {
                continue;
            }
            project.refreshLocal(IResource.DEPTH_INFINITE, monitor);
            if (project.hasNature(JavaCore.NATURE_ID)) {
                javaProjects.add(JavaCore.create(project));
            }
        }

        workspace.build(IncrementalProjectBuilder.CLEAN_BUILD, monitor);
        for (IProject project : projects) {
            if (project.isAccessible()) {
                project.refreshLocal(IResource.DEPTH_INFINITE, monitor);
            }
        }

        workspace.build(IncrementalProjectBuilder.FULL_BUILD, monitor);
        for (IProject project : projects) {
            if (project.isAccessible()) {
                project.refreshLocal(IResource.DEPTH_INFINITE, monitor);
            }
        }

        JavaCore.rebuildIndex(monitor);
        for (IJavaProject javaProject : javaProjects) {
            javaProject.getResolvedClasspath(true);
        }
    }

    private record ImportRequest(List<File> projectDirs, List<File> gradleScanRoots, List<File> xsdScanRoots) {
    }
}
