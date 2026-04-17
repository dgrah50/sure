import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import { sankey } from "d3-sankey";

/**
 * @typedef {Object} SankeyNode
 * @property {number} index - Node index.
 * @property {string} name - Node name.
 * @property {string} [color] - Node color.
 * @property {number} [x0] - Left bound.
 * @property {number} [x1] - Right bound.
 * @property {number} [y0] - Top bound.
 * @property {number} [y1] - Bottom bound.
 * @property {SankeyLink[]} [sourceLinks] - Outgoing links.
 * @property {SankeyLink[]} [targetLinks] - Incoming links.
 * @property {number} [depth] - Node depth in the diagram.
 * @property {number} [value] - Node value.
 */

/**
 * @typedef {Object} SankeyLink
 * @property {SankeyNode} source - Source node.
 * @property {SankeyNode} target - Target node.
 * @property {number} value - Link value.
 * @property {number} [width] - Calculated width.
 * @property {number} [y0] - Source Y position.
 * @property {number} [y1] - Target Y position.
 * @property {string} [percentage] - Display percentage.
 */

/**
 * @typedef {Object} SankeyData
 * @property {SankeyNode[]} nodes - Array of nodes.
 * @property {SankeyLink[]} links - Array of links connecting nodes.
 */

/**
 * Controller for rendering a D3 sankey diagram.
 *
 * This controller creates an interactive SVG sankey diagram with hover effects,
 * tooltips, and gradient links. It supports responsive resizing and dynamic
 * label visibility based on available space.
 *
 * @extends Controller
 */
export default class extends Controller {
  /**
   * Static values for the controller.
   * @type {Object}
   * @property {Object} data - The sankey data (nodes and links).
   * @property {number} nodeWidth - Width of each node.
   * @property {number} nodePadding - Padding between nodes.
   * @property {string} currencySymbol - Currency symbol for formatting.
   */
  static values = {
    data: Object,
    nodeWidth: { type: Number, default: 15 },
    nodePadding: { type: Number, default: 20 },
    currencySymbol: { type: String, default: "$" }
  };

  // Visual constants
  /** @type {number} */
  static HOVER_OPACITY = 0.4;
  /** @type {string} */
  static HOVER_FILTER = "saturate(1.3) brightness(1.1)";
  /** @type {number} */
  static EXTENT_MARGIN = 16;
  /** @type {number} */
  static MIN_NODE_PADDING = 4;
  /** @type {number} */
  static MAX_PADDING_RATIO = 0.4;
  /** @type {number} */
  static CORNER_RADIUS = 8;
  /** @type {string} */
  static DEFAULT_COLOR = "var(--color-gray-400)";
  /** @type {Object<string, string>} */
  static CSS_VAR_MAP = {
    "var(--color-success)": "#10A861",
    "var(--color-destructive)": "#EC2222",
    "var(--color-gray-400)": "#9E9E9E",
    "var(--color-gray-500)": "#737373"
  };
  /** @type {number} */
  static MIN_LABEL_SPACING = 28; // Minimum vertical space needed for labels (2 lines)

  /**
   * Called when the controller is connected to the DOM.
   * Initializes the chart, resize observer, and tooltip.
   * @returns {void}
   */
  connect() {
    this.resizeObserver = new ResizeObserver(() => this.#draw());
    this.resizeObserver.observe(this.element);
    this.tooltip = null;
    this.#createTooltip();
    this.#draw();
  }

  /**
   * Called when the controller is disconnected from the DOM.
   * Cleans up resize observer and tooltip.
   * @returns {void}
   */
  disconnect() {
    this.resizeObserver?.disconnect();
    this.tooltip?.remove();
    this.tooltip = null;
  }

  /**
   * Draws the sankey diagram.
   * @returns {void}
   * @private
   */
  #draw() {
    const { nodes = [], links = [] } = this.dataValue || {};
    if (!nodes.length || !links.length) return;

    // Hide tooltip and reset any hover states before redrawing
    this.#hideTooltip();

    d3.select(this.element).selectAll("svg").remove();

    const width = this.element.clientWidth || 600;
    const height = this.element.clientHeight || 400;

    const svg = d3.select(this.element)
      .append("svg")
      .attr("width", width)
      .attr("height", height);

    const effectivePadding = this.#calculateNodePadding(nodes.length, height);
    const sankeyData = this.#generateSankeyData(nodes, links, width, height, effectivePadding);

    this.#createGradients(svg, sankeyData.links);

    const linkPaths = this.#drawLinks(svg, sankeyData.links);
    const { nodeGroups, hiddenLabels } = this.#drawNodes(svg, sankeyData.nodes, width);

    this.#attachHoverEvents(linkPaths, nodeGroups, sankeyData, hiddenLabels);
  }

  /**
   * Calculates dynamic node padding based on node count and height.
   * @param {number} nodeCount - Number of nodes.
   * @param {number} height - Container height.
   * @returns {number} The calculated padding.
   * @private
   */
  #calculateNodePadding(nodeCount, height) {
    const margin = this.constructor.EXTENT_MARGIN;
    const availableHeight = height - (margin * 2);
    const maxPaddingTotal = availableHeight * this.constructor.MAX_PADDING_RATIO;
    const gaps = Math.max(nodeCount - 1, 1);
    const dynamicPadding = Math.min(this.nodePaddingValue, Math.floor(maxPaddingTotal / gaps));
    return Math.max(this.constructor.MIN_NODE_PADDING, dynamicPadding);
  }

  /**
   * Generates sankey layout data.
   * @param {SankeyNode[]} nodes - Array of nodes.
   * @param {SankeyLink[]} links - Array of links.
   * @param {number} width - Container width.
   * @param {number} height - Container height.
   * @param {number} nodePadding - Padding between nodes.
   * @returns {{nodes: SankeyNode[], links: SankeyLink[]}} The sankey layout data.
   * @private
   */
  #generateSankeyData(nodes, links, width, height, nodePadding) {
    const margin = this.constructor.EXTENT_MARGIN;
    const sankeyGenerator = sankey()
      .nodeWidth(this.nodeWidthValue)
      .nodePadding(nodePadding)
      .extent([[margin, margin], [width - margin, height - margin]]);

    return sankeyGenerator({
      nodes: nodes.map(d => ({ ...d })),
      links: links.map(d => ({ ...d })),
    });
  }

  /**
   * Creates gradient definitions for links.
   * @param {import("d3").Selection<SVGSVGElement, unknown, null, undefined>} svg - The SVG selection.
   * @param {SankeyLink[]} links - Array of links.
   * @returns {void}
   * @private
   */
  #createGradients(svg, links) {
    const defs = svg.append("defs");

    links.forEach((link, i) => {
      const gradientId = this.#gradientId(link, i);
      const gradient = defs.append("linearGradient")
        .attr("id", gradientId)
        .attr("gradientUnits", "userSpaceOnUse")
        .attr("x1", link.source.x1)
        .attr("x2", link.target.x0);

      gradient.append("stop")
        .attr("offset", "0%")
        .attr("stop-color", this.#colorWithOpacity(link.source.color));

      gradient.append("stop")
        .attr("offset", "100%")
        .attr("stop-color", this.#colorWithOpacity(link.target.color));
    });
  }

  /**
   * Generates a unique gradient ID for a link.
   * @param {SankeyLink} link - The link.
   * @param {number} index - The link index.
   * @returns {string} The gradient ID.
   * @private
   */
  #gradientId(link, index) {
    return `link-gradient-${link.source.index}-${link.target.index}-${index}`;
  }

  /**
   * Returns a color with specified opacity.
   * @param {string} nodeColor - The base color.
   * @param {number} [opacity=0.1] - The opacity value.
   * @returns {string} The color with opacity.
   * @private
   */
  #colorWithOpacity(nodeColor, opacity = 0.1) {
    const defaultColor = this.constructor.DEFAULT_COLOR;
    let colorStr = nodeColor || defaultColor;

    // Map CSS variables to hex values for d3 color manipulation
    colorStr = this.constructor.CSS_VAR_MAP[colorStr] || colorStr;

    // Unmapped CSS vars cannot be manipulated, return as-is
    if (colorStr.startsWith("var(--")) return colorStr;

    const d3Color = d3.color(colorStr);
    return d3Color ? d3Color.copy({ opacity }) : defaultColor;
  }

  /**
   * Draws the sankey links.
   * @param {import("d3").Selection<SVGSVGElement, unknown, null, undefined>} svg - The SVG selection.
   * @param {SankeyLink[]} links - Array of links.
   * @returns {import("d3").Selection<SVGPathElement, SankeyLink, null, undefined>} The link paths selection.
   * @private
   */
  #drawLinks(svg, links) {
    return svg.append("g")
      .attr("fill", "none")
      .selectAll("path")
      .data(links)
      .join("path")
      .attr("class", "sankey-link")
      .attr("d", d => d3.linkHorizontal()({
        source: [d.source.x1, d.y0],
        target: [d.target.x0, d.y1]
      }))
      .attr("stroke", (d, i) => `url(#${this.#gradientId(d, i)})`)
      .attr("stroke-width", d => Math.max(1, d.width))
      .style("transition", "opacity 0.3s ease");
  }

  /**
   * Draws the sankey nodes.
   * @param {import("d3").Selection<SVGSVGElement, unknown, null, undefined>} svg - The SVG selection.
   * @param {SankeyNode[]} nodes - Array of nodes.
   * @param {number} width - Container width.
   * @returns {{nodeGroups: import("d3").Selection<SVGGElement, SankeyNode, null, undefined>, hiddenLabels: Set<number>}} Node groups and hidden label set.
   * @private
   */
  #drawNodes(svg, nodes, width) {
    const nodeGroups = svg.append("g")
      .selectAll("g")
      .data(nodes)
      .join("g")
      .style("transition", "opacity 0.3s ease");

    nodeGroups.append("path")
      .attr("d", d => this.#nodePath(d))
      .attr("fill", d => d.color || this.constructor.DEFAULT_COLOR)
      .attr("stroke", d => d.color ? "none" : "var(--color-gray-500)");

    const hiddenLabels = this.#addNodeLabels(nodeGroups, width, nodes);

    return { nodeGroups, hiddenLabels };
  }

  /**
   * Generates the SVG path for a node.
   * @param {SankeyNode} node - The node.
   * @returns {string} The SVG path string.
   * @private
   */
  #nodePath(node) {
    const { x0, y0, x1, y1 } = node;
    const height = y1 - y0;
    const radius = Math.max(0, Math.min(this.constructor.CORNER_RADIUS, height / 2));

    const isSourceNode = node.sourceLinks?.length > 0 && !node.targetLinks?.length;
    const isTargetNode = node.targetLinks?.length > 0 && !node.sourceLinks?.length;

    // Too small for rounded corners
    if (height < radius * 2) {
      return this.#rectPath(x0, y0, x1, y1);
    }

    if (isSourceNode) {
      return this.#roundedLeftPath(x0, y0, x1, y1, radius);
    }

    if (isTargetNode) {
      return this.#roundedRightPath(x0, y0, x1, y1, radius);
    }

    return this.#rectPath(x0, y0, x1, y1);
  }

  /**
   * Generates a rectangle path.
   * @param {number} x0 - Left bound.
   * @param {number} y0 - Top bound.
   * @param {number} x1 - Right bound.
   * @param {number} y1 - Bottom bound.
   * @returns {string} The SVG path string.
   * @private
   */
  #rectPath(x0, y0, x1, y1) {
    return `M ${x0},${y0} L ${x1},${y0} L ${x1},${y1} L ${x0},${y1} Z`;
  }

  /**
   * Generates a rectangle path with rounded left corners.
   * @param {number} x0 - Left bound.
   * @param {number} y0 - Top bound.
   * @param {number} x1 - Right bound.
   * @param {number} y1 - Bottom bound.
   * @param {number} r - Corner radius.
   * @returns {string} The SVG path string.
   * @private
   */
  #roundedLeftPath(x0, y0, x1, y1, r) {
    return `M ${x0 + r},${y0}
            L ${x1},${y0}
            L ${x1},${y1}
            L ${x0 + r},${y1}
            Q ${x0},${y1} ${x0},${y1 - r}
            L ${x0},${y0 + r}
            Q ${x0},${y0} ${x0 + r},${y0} Z`;
  }

  /**
   * Generates a rectangle path with rounded right corners.
   * @param {number} x0 - Left bound.
   * @param {number} y0 - Top bound.
   * @param {number} x1 - Right bound.
   * @param {number} y1 - Bottom bound.
   * @param {number} r - Corner radius.
   * @returns {string} The SVG path string.
   * @private
   */
  #roundedRightPath(x0, y0, x1, y1, r) {
    return `M ${x0},${y0}
            L ${x1 - r},${y0}
            Q ${x1},${y0} ${x1},${y0 + r}
            L ${x1},${y1 - r}
            Q ${x1},${y1} ${x1 - r},${y1}
            L ${x0},${y1} Z`;
  }

  /**
   * Adds labels to nodes.
   * @param {import("d3").Selection<SVGGElement, SankeyNode, null, undefined>} nodeGroups - The node groups.
   * @param {number} width - Container width.
   * @param {SankeyNode[]} nodes - Array of nodes.
   * @returns {Set<number>} Set of hidden label indices.
   * @private
   */
  #addNodeLabels(nodeGroups, width, nodes) {
    const controller = this;
    const hiddenLabels = this.#calculateHiddenLabels(nodes);

    nodeGroups.append("text")
      .attr("x", d => d.x0 < width / 2 ? d.x1 + 6 : d.x0 - 6)
      .attr("y", d => (d.y1 + d.y0) / 2)
      .attr("dy", "-0.2em")
      .attr("text-anchor", d => d.x0 < width / 2 ? "start" : "end")
      .attr("class", "text-xs font-medium text-primary fill-current select-none")
      .style("cursor", "default")
      .style("opacity", d => hiddenLabels.has(d.index) ? 0 : 1)
      .style("transition", "opacity 0.2s ease")
      .each(function (d) {
        const textEl = d3.select(this);
        textEl.selectAll("tspan").remove();

        textEl.append("tspan").text(d.name);

        textEl.append("tspan")
          .attr("x", textEl.attr("x"))
          .attr("dy", "1.2em")
          .attr("class", "font-mono text-secondary")
          .style("font-size", "0.65rem")
          .text(controller.#formatCurrency(d.value));
      });

    return hiddenLabels;
  }

  /**
   * Calculates which labels should be hidden to prevent overlap.
   * @param {SankeyNode[]} nodes - Array of nodes.
   * @returns {Set<number>} Set of hidden label indices.
   * @private
   */
  #calculateHiddenLabels(nodes) {
    const hiddenLabels = new Set();
    const height = this.element.clientHeight || 400;
    const isLargeGraph = height > 600;
    const minSpacing = isLargeGraph ? this.constructor.MIN_LABEL_SPACING * 0.7 : this.constructor.MIN_LABEL_SPACING;

    // Group nodes by column (using depth which d3-sankey assigns)
    const columns = new Map();
    nodes.forEach(node => {
      const depth = node.depth;
      if (!columns.has(depth)) columns.set(depth, []);
      columns.get(depth).push(node);
    });

    // For each column, check for overlapping labels
    columns.forEach(columnNodes => {
      // Sort by vertical position
      columnNodes.sort((a, b) => ((a.y0 + a.y1) / 2) - ((b.y0 + b.y1) / 2));

      let lastVisibleY = Number.NEGATIVE_INFINITY;

      columnNodes.forEach(node => {
        const nodeY = (node.y0 + node.y1) / 2;
        const nodeHeight = node.y1 - node.y0;

        if (isLargeGraph && nodeHeight > minSpacing * 1.5) {
          lastVisibleY = nodeY;
        } else if (nodeY - lastVisibleY < minSpacing) {
          // Too close to previous visible label, hide this one
          hiddenLabels.add(node.index);
        } else {
          lastVisibleY = nodeY;
        }
      });
    });

    return hiddenLabels;
  }

  /**
   * Attaches hover events to links and nodes.
   * @param {import("d3").Selection<SVGPathElement, SankeyLink, null, undefined>} linkPaths - The link paths.
   * @param {import("d3").Selection<SVGGElement, SankeyNode, null, undefined>} nodeGroups - The node groups.
   * @param {{nodes: SankeyNode[], links: SankeyLink[]}} sankeyData - The sankey data.
   * @param {Set<number>} hiddenLabels - Set of hidden label indices.
   * @returns {void}
   * @private
   */
  #attachHoverEvents(linkPaths, nodeGroups, sankeyData, hiddenLabels) {
    const applyHover = (targetLinks) => {
      const targetSet = new Set(targetLinks);
      const connectedNodes = new Set(targetLinks.flatMap(l => [l.source, l.target]));

      linkPaths
        .style("opacity", d => targetSet.has(d) ? 1 : this.constructor.HOVER_OPACITY)
        .style("filter", d => targetSet.has(d) ? this.constructor.HOVER_FILTER : "none");

      nodeGroups.style("opacity", d => connectedNodes.has(d) ? 1 : this.constructor.HOVER_OPACITY);

      // Show labels for connected nodes (even if normally hidden)
      nodeGroups.selectAll("text")
        .style("opacity", d => connectedNodes.has(d) ? 1 : (hiddenLabels.has(d.index) ? 0 : this.constructor.HOVER_OPACITY));
    };

    const resetHover = () => {
      linkPaths.style("opacity", 1).style("filter", "none");
      nodeGroups.style("opacity", 1);
      // Restore hidden labels to hidden state
      nodeGroups.selectAll("text")
        .style("opacity", d => hiddenLabels.has(d.index) ? 0 : 1);
    };

    linkPaths
      .on("mouseenter", (event, d) => {
        applyHover([d]);
        this.#showTooltip(event, d.value, d.percentage);
      })
      .on("mousemove", event => this.#updateTooltipPosition(event))
      .on("mouseleave", () => {
        resetHover();
        this.#hideTooltip();
      });

    // Hover on node rectangles (not just text)
    nodeGroups.selectAll("path")
      .style("cursor", "default")
      .on("mouseenter", (event, d) => {
        const connectedLinks = sankeyData.links.filter(l => l.source === d || l.target === d);
        applyHover(connectedLinks);
        this.#showTooltip(event, d.value, d.percentage, d.name);
      })
      .on("mousemove", event => this.#updateTooltipPosition(event))
      .on("mouseleave", () => {
        resetHover();
        this.#hideTooltip();
      });

    nodeGroups.selectAll("text")
      .on("mouseenter", (event, d) => {
        const connectedLinks = sankeyData.links.filter(l => l.source === d || l.target === d);
        applyHover(connectedLinks);
        this.#showTooltip(event, d.value, d.percentage, d.name);
      })
      .on("mousemove", event => this.#updateTooltipPosition(event))
      .on("mouseleave", () => {
        resetHover();
        this.#hideTooltip();
      });
  }

  /**
   * Creates the tooltip element.
   * @returns {void}
   * @private
   */
  #createTooltip() {
    const dialog = this.element.closest("dialog");
    this.tooltip = d3.select(dialog || document.body)
      .append("div")
      .attr("class", "bg-gray-700 text-white text-sm p-2 rounded pointer-events-none absolute z-50 top-0")
      .style("opacity", 0)
      .style("pointer-events", "none");
  }

  /**
   * Shows the tooltip with content.
   * @param {MouseEvent} event - The mouse event.
   * @param {number} value - The value to display.
   * @param {string} percentage - The percentage to display.
   * @param {string} [title] - Optional title.
   * @returns {void}
   * @private
   */
  #showTooltip(event, value, percentage, title = null) {
    if (!this.tooltip) this.#createTooltip();

    const content = title
      ? `${title}<br/>${this.#formatCurrency(value)} (${percentage || 0}%)`
      : `${this.#formatCurrency(value)} (${percentage || 0}%)`;

    const isInDialog = !!this.element.closest("dialog");
    const x = isInDialog ? event.clientX : event.pageX;
    const y = isInDialog ? event.clientY : event.pageY;

    this.tooltip
      .html(content)
      .style("position", isInDialog ? "fixed" : "absolute")
      .style("left", `${x + 10}px`)
      .style("top", `${y - 10}px`)
      .transition()
      .duration(100)
      .style("opacity", 1);
  }

  /**
   * Updates tooltip position on mouse move.
   * @param {MouseEvent} event - The mouse event.
   * @returns {void}
   * @private
   */
  #updateTooltipPosition(event) {
    if (this.tooltip) {
      const isInDialog = !!this.element.closest("dialog");
      const x = isInDialog ? event.clientX : event.pageX;
      const y = isInDialog ? event.clientY : event.pageY;

      this.tooltip
        ?.style("left", `${x + 10}px`)
        .style("top", `${y - 10}px`);
    }
  }

  /**
   * Hides the tooltip.
   * @returns {void}
   * @private
   */
  #hideTooltip() {
    if (this.tooltip) {
      this.tooltip
        ?.transition()
        .duration(100)
        .style("opacity", 0)
        .style("pointer-events", "none");
    }
  }

  /**
   * Formats a value as currency.
   * @param {number} value - The value to format.
   * @returns {string} The formatted currency string.
   * @private
   */
  #formatCurrency(value) {
    const formatted = Number.parseFloat(value).toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    });
    return this.currencySymbolValue + formatted;
  }
}
